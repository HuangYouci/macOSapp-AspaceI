# AspaceI 架構概覽

最後更新日期：2026-10-09

對應功能／commit：非預設實例改用 App 複本（Dock 圖示右下角標使用者名稱前兩字）；多開與 App 自動更新衝突（更新並重開、預設實例改用 `open -n`）；Claude 實例自動辨識登入帳號、實例刪除入口修正（列尾選單、整列右鍵、二次確認）；Antigravity 切換改寫登入 Keychain、寫入驗證與空殼憑證防線、Gemini 額度群組與 5h 時窗修正、同 email 帳號合併

## 邊界

AspaceI 採本機優先架構。畫面只呈現注入的帳號及額度狀態，不直接存取登入檔案、Keychain 或遠端服務。

## 資料流

1. `CredentialImportService` 讀取既有憑證後立即交給 `KeychainService`，不輸出內容。
2. `QuotaService` 在記憶體內取得 token 並轉換各平台回應。
3. `AccountManager` 協調匯入、額度與非敏感資料保存。
4. `ExecutableLocatorService` 只做唯讀路徑探測，回傳各平台預設可執行檔位置供建立 Instance 使用。
5. `MenuBarContentView` 僅接收 `AccountManager` 與 `InstanceManager` 提供的資料；`MenuBarLabel` 只接收 `MenuBarQuotaItem` 陣列。

額度語意統一為「剩餘百分比 + 時窗種類」。時窗只認三種，標籤統一：5h = 段（S）、7d = 週（W）、1m = 月（M）；其他長度的時窗在解析階段就丟棄，不顯示。標籤走 `Resources/Localization` 的 `Localizable.strings`（zh-Hant 為預設，en 為 S／W／M）。

| 平台 | 端點 | 時窗 |
| :--- | :--- | :--- |
| Codex | `chatgpt.com/backend-api/wham/usage` | `primary_window`／`secondary_window` 依 `limit_window_seconds` 判定；Pro 等方案可能只有 7d |
| Claude | `api.anthropic.com/api/oauth/usage` | `five_hour`、`seven_day` |
| Antigravity | `<host>/v1internal:retrieveUserQuotaSummary`，host 見下 | 只取 Gemini 群組的 5h／7d；Claude/GPT 群組不提供；`disabled` 時窗略過。找不到 Gemini 群組就整筆丟棄，不退回第一個群組（否則會把 `3p-*` 的數字掛到 Gemini 欄位）。週限額用完時 5h 桶會回週的重置時間與被壓住的比例，此時視為 5h 未使用：顯示 100% 且不顯示倒數。判定沿用 cockpit-tools `getAntigravityQuotaDisplayItems`，但多要求 5h 的重置時間不早於週的——沒用過的 5h 視窗本來就回「現在 + 5 小時」，單看「距今超過五小時」會在邊界誤判而抹掉還在走的倒數（2026-09-18 實測：5h 重置 5.08 小時後、週重置 6.2 小時後，兩個都還沒被壓住） |
| GitHub Copilot | `api.github.com/copilot_internal/user` | 每月重置；有 premium 額度時取 `premium_interactions`，免費方案退回 `chat` |

#### Antigravity 的後端有兩個

`cloudcode-pa.googleapis.com`（prod）只服務 GCP ToS 帳號；其餘（含所有消費者方案）的使用量記在
`daily-cloudcode-pa.googleapis.com`。**問錯後端不會報錯**，只會回一份沒有任何使用紀錄的額度：
所有桶都是 100%，`resetTime` 是「現在 + 視窗長度」。2026-09-18 實測同一個 token 同時打兩個 host，
prod 回 100%／100%，daily 回 87%／21%，後者才和官方 App 畫面一致。

判定沿用 cockpit-tools 的 `resolve_cloud_code_base_url` 與 `create_oauth_info_with_metadata`：
`standard-tier` 走 prod，其餘走 daily；`@gmail.com`／`@googlemail.com` 一律走 daily，即使 tier 對得上。
tier id 存在 `Account.tierID`，每輪從 `loadCodeAssist` 更新——它同時決定後端與方案，而帳號第一次
出現時手上還沒有 tier，所以預設值必須是 daily。`loadCodeAssist` 也要打同一個 host。

額度每五分鐘在背景更新；失敗時保留最後一次成功快取並於帳號列顯示狀態。同一時間只跑一輪（期間再被呼叫就排到下一輪），避免兩輪同時換發輪替式 refresh token。

### Token 保活

- 本機匯入的帳號：每輪先從官方客戶端的檔案重新讀取憑證（只讀檔案），內容變了才寫回 Keychain；由官方客戶端負責換新。寫回前先確認檔案屬於該帳號（`AccountManager.localFile`）：能從 id_token 取得身分就比對身分，取不到就比對 refresh token（Google 的不輪替），兩者都判斷不出來時只信任 `origin == .local` 的帳號。少了這道判斷，使用者在官方 App 裡換回別的帳號後，AspaceI 會把官方 App 的憑證蓋到切換進來的帳號上，畫面看起來就像「切換沒有生效」。
- AspaceI 自己登入或從檔案匯入的帳號：Claude 在 `expiresAt` 前一分鐘換新；Codex 在 `last_refresh` 超過 7 天（或沒有紀錄）時換新；兩者遇到 401/403 也會換新重試。Antigravity 每次都用 refresh token 換 access token；GitHub device flow token 不會過期。
- 只在 App 執行時運作，需要常駐請開「登入時開啟」。

### 方案

| 平台 | 來源 |
| :--- | :--- |
| Codex | usage 回應的 `plan_type`；`prolite` 為 Pro 5x，`promax` 或單純 `pro` 視為 Pro 20x（沿用 cockpit-tools 判定，API 目前不區分） |
| Claude | `api/oauth/profile` 的 `organization.rate_limit_tier`（Max 5x/20x）或 `organization_type` |
| Antigravity | `loadCodeAssist` 的 `paidTier.id`，沒有才看 `currentTier.id` |
| GitHub Copilot | `copilot_internal/user` 的 `access_type_sku` 與 `copilot_plan` |

Claude 與 Antigravity 的方案需要額外請求，只在帳號還沒有方案時查一次。額度表以灰色膠囊顯示方案；目前帳號以粗體呈現，其餘帳號為次要色。

## App 生命週期與介面

- App 採 accessory activation policy，不顯示 Dock 圖示。
- App 只有 menu bar popup，不建立一般主視窗或漂浮視窗。
- Popup 分為額度、實例、設定三個分頁；帳號管理併入額度分頁，以單列卡片呈現並由列尾選單切換帳號。
- Popup 固定 456 × 640，各分頁內容自行捲動。曾嘗試高度隨內容並錨定左上角，但 MenuBarExtra 視窗縮放時仍會跳動，因此改為固定尺寸（2026-09-13 決策）。加入帳號與新增實例在 popup 內切換畫面，不使用 sheet。
- 字級：macOS 不支援 Dynamic Type，popup 內一律使用 `Font.scaled(_:)`，以系統文字樣式基準放大 1.2 倍；根視圖設定 `.scaled(.body)` 讓控制項文字一併放大。
- MenuBarExtra 視窗不吃 `preferredColorScheme`，以 `PopupWindowConfigurator` 直接設定 NSWindow 為 aqua。
- Menu bar 最多顯示三個使用者在設定勾選的帳號，格式為「平台單色標誌 帳號前三字 5h% 7d%」，以 `|` 分隔；多段內容以 `ImageRenderer` 畫成單張 template 圖交給系統上色。未勾選時只顯示 App 單色圖示。帳號名稱取 email／login 的使用者名稱。
- App Icon 原始檔為 `Support/AppIcon.icon`（Icon Composer 格式），`build-app.sh` 以 `actool` 編譯為 `Assets.car` 與 `AppIcon.icns`；menu bar 圖示與平台單色標誌為 `Resources/Logos/*-glyph.png`。
- 額度頁（`QuotaTableView`）每個平台一張卡片，卡片標題列同時是欄名（段／週／月），三欄在所有卡片對齊以便比較；沒有該時窗顯示「–」。只顯示百分比，不用顏色區分高低。底部顯示最近一次更新時間。
- 有百分比的格子在下方顯示該時窗的重置倒數（`QuotaCountdown`）：最多兩個時間單位，第二個單位為零時只顯示一個，已重置則不顯示。整張表包在 `TimelineView(.periodic(from:by:))` 的每秒節拍裡重畫，popup 收起後視圖消失就不再更新。
- popup 內的二次確認一律用 `ConfirmationOverlay` 蓋在畫面上，不用 `confirmationDialog`／`alert`：MenuBarExtra 的面板不會成為 key window，系統對話框畫得出來但收不到點擊。確認請求由畫面外部注入（`ConfirmationRequest`），統一由 `MenuBarContentView` 呈現。
- 卡片一律使用 `cardStyle()`：白底、連續圓角、極淡陰影，不畫外框。
- 平台彩色圖示取用 `Sources/AspaceI/Resources/Logos/` 內的官方標誌，經 `Bundle.module` 載入；`scripts/build-app.sh` 必須將 SwiftPM resource bundle 一併複製進 `.app`。
- 使用者只能從 popup 的「結束 AspaceI」真正終止 App。
- 登入時開啟採用系統 `SMAppService.mainApp`，不自行維護 LaunchAgent。

## 加入帳號

登入流程狀態由 `AccountLoginManager` 持有（在 `@main` 建立並注入），不能放在畫面裡：使用者切到瀏覽器時 popup 會收起、畫面消失，若流程跟著畫面走，loopback 回呼會被取消、Claude 貼授權碼時也找不到原本的 PKCE。popup 再打開時，若流程還在進行或失敗會自動回到加入帳號畫面；在背景完成則直接關閉流程。

加入帳號畫面上方選平台（四個圖示卡片），下方三張方式卡片：瀏覽器登入、讀取這台 Mac（顯示該平台官方檔案路徑與是否找到，只讀該平台）、貼上或拖入（文字框接受貼上、拖入檔案或選擇檔案）。貼上內容由 `CredentialDetector` 依形狀判斷是哪個平台的憑證或帳號備份檔，辨識到的平台優先於上方選擇；辨識不出來才用所選平台。流程狀態由 `AccountLoginFeature` 持有，網路與格式轉換在 `OAuthService`。

| 平台 | 流程 | 回呼 |
| :--- | :--- | :--- |
| Codex | PKCE authorization code | `OAuthCallbackServer` 聽 `localhost:1455/auth/callback`（官方註冊的固定埠，官方客戶端登入中會衝突） |
| Antigravity | PKCE + client secret，`access_type=offline` | `localhost:51121/oauth-callback` |
| Claude | PKCE，官方手動回呼頁 | 使用者把頁面上的 `code#state` 貼回 App |
| GitHub Copilot | Device flow（Copilot GitHub App client） | 輪詢；使用者碼自動複製並開啟驗證頁 |

OAuth 取得的憑證寫成各官方客戶端的原生格式（Codex `auth.json`、Claude Code `.credentials.json`、Antigravity `jetski-standalone-oauth-token`），因此可直接投影到實例或官方客戶端。Antigravity 另外保留回應中的 `id_token`，它同時是官方檔案的登入身分與 AspaceI 判斷憑證屬於誰的依據。同平台同 email 的帳號視為同一人，重新登入時覆寫憑證；本機匯入的帳號也算在內，合併時保留 `origin == .local`（換新仍由官方客戶端負責）。先前排除 `.local` 會讓同一個 Google 帳號變成兩列、額度數字一模一樣，互相切換看起來沒作用。

### Token 輪替

Codex 與 Claude 的 refresh token 會輪替。只有 `origin` 不是 `.local` 的帳號才會在額度請求回 401/403（Claude 另在 `expiresAt` 前一分鐘）時換發並寫回 Keychain；本機匯入的憑證屬於官方客戶端，AspaceI 換發會讓官方客戶端被登出。

### 匯入／匯出

設定頁「帳號備份」匯出全部帳號為 `aspacei.accounts` v1 JSON（含完整憑證，檔案權限 0600，匯出前確認）。匯入同時接受此格式與其他工具（例如 cockpit-tools）的帳號陣列，依欄位形狀判斷平台：`tokens` → Codex、`claudeAiOauth` → Claude、`github_access_token`／`gh*` token → GitHub、`refresh_token` → Antigravity。加入帳號畫面的「匯入檔案」先嘗試帳號檔，失敗再當成所選平台的單一憑證。

## 機密資料

- Token 與 refresh token 只存入 macOS Keychain，而且集中成單一項目（service `com.huangyouci.AspaceI`、account `credentials-vault`，內容為 reference → 憑證的 JSON），啟動後讀一次並快取在記憶體。macOS 對每個項目各自要求授權，分散存放時帳號越多跳越多次。舊版每帳號一個項目的資料在第一次讀到時併入並刪除。
- `build-app.sh` 優先使用本機的 Apple Development／Developer ID 簽章。Keychain 依簽章判斷是否為同一個 App；ad-hoc 簽章每次建置都會變，導致「永遠允許」失效而反覆詢問。
- 啟動時的自動匯入只讀檔案（`~/.codex/auth.json`、`~/.claude/.credentials.json`、`gh auth token`），不讀其他 App 的 Keychain 項目；那些只在使用者按「本機偵測」時讀取。Antigravity 的 `gemini`／`antigravity` 項目是例外，它就是官方 App 現行的登入位置，而且讀取不跳授權視窗，等同於讀檔案。
- 一般 JSON 僅保存帳號識別資訊、平台、方案、額度快取及重置時間。
- Log 不得包含 token、Authorization header、Cookie 或原始登入檔案內容。
- GitHub 使用官方 `gh auth token` 從系統 Keychain 取值，轉存時只寫入 AspaceI Keychain；啟動綁定 Instance 時以環境變數注入。

## 多 Instance

實例一律是桌面 App，依服務分組：VS Code（GitHub Copilot）、Antigravity、Claude、Codex。App 由 `ExecutableLocatorService` 在 `/Applications` 與 `~/Applications` 尋找；未安裝時整組停用。

- 每組第一個是「預設」實例：不存檔、不可刪除，id 依平台固定。以 `open -n -a` 開啟系統原本的 App 設定。`-n` 不能省：同一個 App 已有其他實例在跑時，沒有 `-n` 的 `open` 只會把其中一個（不一定是哪個）叫到前面，預設實例根本沒開（2026-10-09 使用者回報「再開啟不一定是我要的 Instance」）。啟動只在實例沒有執行時發生；萬一狀態過期多開了一個，Electron 的單一實例鎖會讓它把焦點交給原本那個後自行結束。
- 其他實例以 `open -n -a <複本> --args --user-data-dir=<資料夾>` 開新程序（2026-09-14 四平台實測；複本見下方「非預設實例的 App 名稱與圖示」）：
  - 必須用等號形式；Claude 會忽略空格分開的寫法，改用預設資料夾。
  - Codex（ChatGPT.app）另以 `--env CODEX_HOME=<資料夾>`、`--env CODEX_ELECTRON_USER_DATA_PATH=<資料夾>/app-data`；新版只認這個環境變數，沒設的話第二個程序會被單一實例鎖直接結束。
  - Claude 正式版會刪掉 `CLAUDE_USER_DATA_DIR`，不再傳。
  - 實例資料夾名稱取 UUID 前 8 碼：VS Code 在資料夾內建立 IPC socket，完整 UUID 會超過 macOS 104 字元的 socket 路徑上限而啟動即結束。舊實例沿用已存的路徑。
  - `open` 會把呼叫端的環境變數轉交給 App，啟動時濾掉 `DYLD_*`。
- 執行狀態以 `ps` 比對主執行檔：`.app/Contents/MacOS/` 之前的路徑不能再有 `/Contents/`（排除 Frameworks 裡的 Helper）也不能有引號（排除 VS Code 讀 shell 環境的 `/bin/zsh -c '…/Code'`）。預設實例是原本 App 名稱（只比對名稱，因為隔離中的 App 會從 AppTranslocation 暫存路徑執行）、沒有 `--user-data-dir`、不在複本資料夾的那個；其他實例不看 App 名稱（複本檔名會變），只比對資料夾（等號與空格兩種寫法都認）。停止送 SIGTERM。
- 帳號綁定只在 AspaceI 能把憑證放到 App 讀得到的位置時提供：Codex（預設與獨立實例，寫入 `auth.json`）、Antigravity 預設實例（寫入官方 token 檔）。Claude Desktop 與 VS Code 的登入存在各自加密的儲存區，不提供綁定，實例內自行登入一次。
- Claude 實例（含預設）改為**自動辨識**目前登入的帳號，列上只顯示、不提供選單：讀該實例資料夾 `config.json` 的 `lastKnownAccountUuid`，同時要有非空的 `oauth:tokenCache*` 才算登入中（`lastKnown` 登出後可能殘留，這一點未實測登出行為），再對到 `Account.accountUUID`（Claude `api/oauth/profile` 的 `account.uuid`，帳號沒有時每輪補抓）。2026-10-08 實測兩者同一套編號：`~/.claude.json` 的 `oauthAccount.accountUuid` 與預設 Claude 相同，兩個實例都對到正確帳號。不能做成像 Codex 的選單：AspaceI 手上是 Claude Code 的 OAuth token，桌面 App 的登入是 claude.ai cookie 與 safeStorage 加密的 token 快取，寫不進去。登入狀態在打開實例分頁與按更新時重讀。
- `instances.json` 為 `{instances, defaultAccountIDs}`，仍可讀舊版只有陣列的格式。

### 多開與 App 自動更新

Claude（Squirrel／ShipIt）、VS Code（Squirrel）、Codex（Sparkle）的更新程式都要等**同一個 App 的所有程序**結束才換掉 App。多開時這個條件永遠不成立，造成：

- Claude 下載好更新、閒置一段時間後會自己結束來安裝（記錄檔 `[stealth-update]`／`beforeQuitForUpdate`），但 ShipIt 等不到其他實例結束，**安裝不會發生、結束的那個實例也不會被重新打開**——使用者看到的是「多開被關閉」。2026-10-09 實測：12:25 關掉 2-big、12:30 關掉預設實例，1-big 一直開著，ShipIt 從 05:19 起每次都停在 `Detected this as an install request`，`main.log` 每次啟動都報 `Previous update install did not apply`。所有實例共用 `~/Library/Logs/Claude/main.log`，要以記錄中的 user-data-dir 或 session 檔所在資料夾判斷是哪個實例。
- 等到使用者把全部關掉，ShipIt 才安裝，`launchAfterInstallation` 為真時只會開 `/Applications/Claude.app`（不帶參數 = 預設實例）。
- Codex 的 Sparkle `Autoupdate` 也是同樣情形（當天 16:22 起一直在等）。

非預設實例改用各自的複本後，原本 App 只剩預設實例會擋住它的更新程式，問題自然消失（Squirrel 只等同一路徑的程序）。過渡期仍可能有從原本 App 開的非預設實例：`refreshRunning` 以 `ps` 找原本 App 的 `Squirrel.framework/Resources/ShipIt` 或 `Sparkle.framework/…/Autoupdate`，**而且**有非預設實例直接從原本 App 執行時，該組標題顯示「更新並重開」。確認後只關從原本 App 執行的實例、等主程序結束（10 秒）、等更新程式結束（60 秒），再開回來（非預設實例就此改用複本）；更新逾時也照樣開回來。App 自己先結束的那個實例不在清單裡，要手動開。Sparkle 是否也只等同一路徑未驗證。

### 非預設實例的 App 名稱與圖示

Dock 顯示的是程序所屬 bundle 的圖示，執行中無法從外部改（2026-10-09 實測）：`_LSSetApplicationInformationItem` 對別的程序設顯示名稱回傳 0 但不生效；Claude 的 Electron fuses 關掉了 `RunAsNode`、`NODE_OPTIONS`、`--inspect` 且啟用 asar 完整性檢查，無法注入；Dock 標記只在 App 內部設定；`disableAutoUpdates` 是依 bundle id 套用到所有 Claude 的企業政策。

因此每個非預設實例啟動前由 `AppCloneService` 準備一份**複本**，四個平台都一樣：

- 位置：`Application Support/AspaceI/Apps.noindex/<實例 id 前 8 碼小寫>/<App 名稱> - <使用者名稱>.app`。`.noindex` 讓 Spotlight 不收錄——從 Spotlight 直接打開複本會開到預設資料夾。
- `clonefile` 整包複製（APFS，不到 1 秒、幾乎不佔空間），不動 `Contents`、不重簽；簽章與 bundle id 不變，`codesign --verify` 與原 designated requirement 都通過，Keychain 不再詢問、TCC 權限沿用。只在 bundle 根目錄以 `NSWorkspace.setIcon` 寫 `Icon\r`（`--strict` 會因此失敗，一般驗證不受影響）。
- 圖示：原本 App 的圖示右下角疊深色膠囊與使用者名稱前兩個字母或數字（`InstanceIconRenderer`）。使用者名稱：Claude 取實例 `config.json` 辨識到的帳號，Codex 取綁定的帳號，其他或不知道時用實例名稱。每次啟動都重畫，帳號變了下次啟動就會更新。
- 原本 App 帶 `com.apple.quarantine` 時（實測 VS Code 有）複本會移除它：原版已經過使用者確認，複本換了位置會被再問一次或改從暫存路徑執行。
- 版本：複本比原本 App 舊就刪掉重做；複本自己更新過（ShipIt 可能把檔名改回 `Claude.app`）而比原版新就沿用、改回實例名稱。版本直接讀 Info.plist，`Bundle(url:)` 依路徑快取會回舊值。
- **Dock 名稱改不了**：滑鼠移到圖示上仍是 `Claude`（`CFBundleName`），要改就得改 Info.plist、簽章失效，回到重簽的代價（`keychain-access-groups` 等受限權限、library validation、TCC）。檔名只在 Finder 看得到。
- `claude://` 的預設處理者仍是 `/Applications/Claude.app`，複本只是候選。
- 複本更新：ShipIt 安裝完重開時不帶參數，開到預設資料夾。`InstanceManager.startMonitoring` 監看 `didLaunchApplicationNotification`，在複本資料夾內、命令列沒有 `--user-data-dir` 的程序一律關掉，改以實例資料夾重開（順便把檔名與圖示改回來）。AspaceI 沒在執行時這段不會發生。
- `ShipItState.plist` 在 `~/Library/Caches/com.anthropic.claudefordesktop.ShipIt/`，同 bundle id 共用：複本下載更新時會把狀態改成指向自己，蓋掉原本 App 排好的安裝；原本 App 下次檢查更新（約 20 分鐘到 1 小時）會重新排。帶 `Icon\r` 的複本能否被 ShipIt 成功更新未驗證；失敗也無妨，AspaceI 會在原本 App 更新後重新複製。
- 刪除實例時一併刪除複本資料夾（可重建的衍生資料，不進垃圾桶）。

2026-10-09 實測：以正式程式碼建立 Claude 與 VS Code 複本，用測試資料夾開啟後 Dock 顯示帶字樣的圖示，簽章驗證通過、沒有跳鑰匙圈詢問。

刪除 Instance 時先送 SIGTERM 並等主程序結束（最多 10 秒，逾時則不刪），否則還在跑的 App 會把資料夾寫回來。只允許處理 `Application Support/AspaceI/Instances/` 的直接子目錄，並移至垃圾桶以保留復原能力；外部路徑一律拒絕。

刪除入口是列尾 ⋮ 選單與整列右鍵，經 `ConfirmationOverlay` 確認。早期只掛 `.contextMenu` 而列上沒有 `contentShape`，名稱與按鈕之間的空白收不到右鍵，使用者回報「實例刪不掉」（2026-10-08）；當時實測 Claude／Codex 實例 SIGTERM 0.3 秒內結束、移到垃圾桶與寫回 `instances.json` 都正常，問題只在入口。Codex 實例關閉後 crashpad 與 git 子程序會殘留幾秒，資料夾已在垃圾桶，不影響刪除。

### 切換帳號

「切換」＝把預設實例（官方 App）換成這個帳號，目前只支援 Codex（寫 `~/.codex/auth.json`，需要完整 tokens）與 Antigravity（寫 `~/.gemini/jetski-standalone-oauth-token`）。

Antigravity 的登入位置隨版本改變，`< 2.0` 在 `state.vscdb`，**`>= 2.0` 在 macOS 登入 Keychain**（service `gemini`、account `antigravity`，內容為 go-keyring 的 `go-keyring-base64:<base64(JSON)>`）。`~/.gemini/jetski-standalone-oauth-token` 只是附帶產物，官方 App 不從那裡讀登入身分。2026-09-18 實測這台 Mac：Antigravity.app 2.14.0，Keychain 內是 A 帳號、jetski 檔案內是 B 帳號，兩者長期不同步——先前只寫檔案的版本切換一律不生效，額度顯示的也是官方 App 已經不在用的那個帳號。判定與封裝形狀比對自 cockpit-tools `antigravity_credential.rs` 與 `commands/account.rs`（`>= 2.0.0` 走 SystemCredential，版本解析不出來時也走這條）。

`AntigravitySystemCredentialService` 負責這個項目。**讀取只在使用者主動按「讀取這台 Mac」時進行**：AspaceI 自己寫入時用的是「允許所有程式」，但官方 App 每次自己換 token 都會把項目重寫成只信任它自己，背景輪詢去讀就會每五分鐘跳一次 Keychain 密碼框（2026-09-18 實際踩到）。背景路徑完全不呼叫，退回 jetski 檔案——它可能停在舊帳號，那是可以接受的代價。cockpit-tools 在 macOS 上根本不讀這個項目（`read_antigravity_system_credential` 只編進 Windows），推測是同一個原因。`load(allowPrompt:)` 在 false 時另外帶 `kSecUseAuthenticationUISkip` 當第二層保險，但不靠它決定要不要讀。

寫必須走 `/usr/bin/security add-generic-password -A`，先刪再加。以 `SecItemAdd` 建立的項目只有 AspaceI 自己能讀，官方 App 會被 Keychain 拒絕而當成沒登入。憑證只能放在 `-w` 的參數值裡：`-w` 不帶值改由 stdin 讀時，`security` 會在 **128 個字元處無聲截斷**（2026-09-18 實測送 418 字元讀回 128），寫出半截 JSON 把官方 App 的登入弄壞。代價是憑證短暫出現在行程參數列，與 cockpit-tools 相同。

寫入有三道防線，缺一不可——這個項目是官方 App 唯一的登入來源，寫壞就是把使用者登出：

1. **寫出去的憑證必須可用**：`isUsableAntigravityToken` 要求 access token 非空且 expiry 不是 1970 預設值。只有 refresh token 的憑證一律擋下讓切換失敗，不寫半份出去。
2. **寫完讀回逐位元組比對**：Keychain 寫入不回報長度，不驗就會把截斷當成切換成功。
3. **失敗還原**：寫入前留住原項目，狀態碼非零或比對不符就放回去。

`CredentialProjectionService.projectToDefaultClient` 的 `writeSystemCredential` 必須可抽換。這個目的地是系統層級的，不隨 `homeDirectory` 改變：2026-09-18 有一次 `swift test` 用預設寫入器把測試用的 `{"refresh_token":"1//r"}` 寫進了開發機上 Antigravity 正在用的登入，測試自己的臨時 home 完全擋不住。凡是寫到 `homeDirectory` 以外的服務，測試都要注入假的寫入器。

jetski 檔案仍然同步寫一份給 Gemini CLI 與舊版用，寫失敗不影響結果。

切換前一定先用 refresh token 換一份可用的 access token（`OAuthService.refreshAntigravity`），連同 `id_token` 與未來的 `expiry` 一起寫進去，換發結果同時寫回 AspaceI 的 Keychain 並把 id_token 裡的 email 補進帳號。只寫 refresh token、access token 留空、expiry 給 1970 的內容不算切換成功：官方 App（Electron）自己保有 Google 登入 session，拿到不能用的憑證會靜默回到原本的帳號。換不到新 token 且手上的 access token 也過期時，直接把換發失敗的原因丟出去讓切換失敗，不寫半份憑證。

比對過 cockpit-tools（2026-09-13 的資料目錄）：它每個 Antigravity 帳號只存 `email` 與 `refresh_token`，沒有任何 access token 或 IDE 狀態快照，所以切換當下必然是自己去換 token。實測該 refresh token 仍可換到帶 `openid` scope 的回應（含 `id_token`），因此 AspaceI 的授權 scope 也補上 `openid`，自己登入的帳號才拿得到 id_token。這台 Mac 上現行的 Antigravity 把登入放在 `~/.gemini/jetski-standalone-oauth-token`，Application Support 內沒有 `state.vscdb`（舊版 Antigravity IDE 才有）。Claude Desktop、VS Code 的登入存在各自加密的儲存區，只能「設為目前帳號」（僅影響 AspaceI 內的粗體標示）。

流程由 `InstanceManager.switchDefault` 負責：官方 App 在執行時先確認 → SIGTERM 並等到主程序結束（最多 10 秒，逾時則不切換）→ `AccountManager.switchDefaultClient` 寫檔、記錄 `defaultClientAccountIDs`、設為目前帳號 → 重新開啟 App。

`defaultClientAccountIDs`（UserDefaults）記錄哪個帳號正在官方 App 裡；沒有紀錄時視為本機匯入的帳號。這個帳號的影響：
- 每輪同步官方檔案時寫回的是它，不是固定寫回本機帳號（否則切換後會把 B 的 token 寫進 A）。Codex 另比對 id_token 的 email，對不上就不寫。
- 它的 token 交給官方 App 換新，AspaceI 不輪替。
- 啟動時目前帳號（粗體）與它對齊。

刪除帳號需二次確認；刪掉本機匯入的帳號後，啟動時的自動匯入會略過該平台，直到使用者按「讀取這台 Mac」。

App 以 bundle identifier 尋找（`NSWorkspace.urlForApplication(withBundleIdentifier:)`），因為 App 會改名：Codex 現在是 `ChatGPT.app`（`com.openai.codex`）。
