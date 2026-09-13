# AspaceI 架構概覽

最後更新日期：2026-09-14

對應功能／commit：AspaceI 26.9.13 帳號切換（預設實例）、刪除確認、Codex 方案 5x/20x；多實例啟動修正（四平台實測）

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
| Antigravity | `cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary` | 只取 Gemini 群組的 5h／7d；Claude/GPT 群組不提供；`disabled` 時窗略過 |
| GitHub Copilot | `api.github.com/copilot_internal/user` | 每月重置；有 premium 額度時取 `premium_interactions`，免費方案退回 `chat` |

額度每五分鐘在背景更新；失敗時保留最後一次成功快取並於帳號列顯示狀態。同一時間只跑一輪（期間再被呼叫就排到下一輪），避免兩輪同時換發輪替式 refresh token。

### Token 保活

- 本機匯入的帳號：每輪先從官方客戶端的檔案重新讀取憑證（只讀檔案），內容變了才寫回 Keychain；由官方客戶端負責換新。
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

OAuth 取得的憑證寫成各官方客戶端的原生格式（Codex `auth.json`、Claude Code `.credentials.json`、Antigravity `jetski-standalone-oauth-token`），因此可直接投影到實例或官方客戶端。同平台同 email 的帳號視為同一人，重新登入時覆寫憑證。

### Token 輪替

Codex 與 Claude 的 refresh token 會輪替。只有 `origin` 不是 `.local` 的帳號才會在額度請求回 401/403（Claude 另在 `expiresAt` 前一分鐘）時換發並寫回 Keychain；本機匯入的憑證屬於官方客戶端，AspaceI 換發會讓官方客戶端被登出。

### 匯入／匯出

設定頁「帳號備份」匯出全部帳號為 `aspacei.accounts` v1 JSON（含完整憑證，檔案權限 0600，匯出前確認）。匯入同時接受此格式與其他工具（例如 cockpit-tools）的帳號陣列，依欄位形狀判斷平台：`tokens` → Codex、`claudeAiOauth` → Claude、`github_access_token`／`gh*` token → GitHub、`refresh_token` → Antigravity。加入帳號畫面的「匯入檔案」先嘗試帳號檔，失敗再當成所選平台的單一憑證。

## 機密資料

- Token 與 refresh token 只存入 macOS Keychain，而且集中成單一項目（service `com.huangyouci.AspaceI`、account `credentials-vault`，內容為 reference → 憑證的 JSON），啟動後讀一次並快取在記憶體。macOS 對每個項目各自要求授權，分散存放時帳號越多跳越多次。舊版每帳號一個項目的資料在第一次讀到時併入並刪除。
- `build-app.sh` 優先使用本機的 Apple Development／Developer ID 簽章。Keychain 依簽章判斷是否為同一個 App；ad-hoc 簽章每次建置都會變，導致「永遠允許」失效而反覆詢問。
- 啟動時的自動匯入只讀檔案（`~/.codex/auth.json`、`~/.claude/.credentials.json`、Antigravity token 檔、`gh auth token`），不讀其他 App 的 Keychain 項目；那些只在使用者按「本機偵測」時讀取。
- 一般 JSON 僅保存帳號識別資訊、平台、方案、額度快取及重置時間。
- Log 不得包含 token、Authorization header、Cookie 或原始登入檔案內容。
- GitHub 使用官方 `gh auth token` 從系統 Keychain 取值，轉存時只寫入 AspaceI Keychain；啟動綁定 Instance 時以環境變數注入。

## 多 Instance

實例一律是桌面 App，依服務分組：VS Code（GitHub Copilot）、Antigravity、Claude、Codex。App 由 `ExecutableLocatorService` 在 `/Applications` 與 `~/Applications` 尋找；未安裝時整組停用。

- 每組第一個是「預設」實例：不存檔、不可刪除，id 依平台固定。以 `open -a` 開啟系統原本的 App 設定。
- 其他實例以 `open -n -a <App> --args --user-data-dir=<資料夾>` 開新程序（2026-09-14 四平台實測）：
  - 必須用等號形式；Claude 會忽略空格分開的寫法，改用預設資料夾。
  - Codex（ChatGPT.app）另以 `--env CODEX_HOME=<資料夾>`、`--env CODEX_ELECTRON_USER_DATA_PATH=<資料夾>/app-data`；新版只認這個環境變數，沒設的話第二個程序會被單一實例鎖直接結束。
  - Claude 正式版會刪掉 `CLAUDE_USER_DATA_DIR`，不再傳。
  - 實例資料夾名稱取 UUID 前 8 碼：VS Code 在資料夾內建立 IPC socket，完整 UUID 會超過 macOS 104 字元的 socket 路徑上限而啟動即結束。舊實例沿用已存的路徑。
  - `open` 會把呼叫端的環境變數轉交給 App，啟動時濾掉 `DYLD_*`。
- 執行狀態以 `ps` 比對：主執行檔位於 `<App 名稱>.app/Contents/MacOS/`（只比對 App 名稱，因為隔離中的 App 會從 AppTranslocation 暫存路徑執行），預設實例是沒有 `--user-data-dir` 的那個，其他以資料夾比對（等號與空格兩種寫法都認）；停止送 SIGTERM。
- 帳號綁定只在 AspaceI 能把憑證放到 App 讀得到的位置時提供：Codex（預設與獨立實例，寫入 `auth.json`）、Antigravity 預設實例（寫入官方 token 檔）。Claude Desktop 與 VS Code 的登入存在各自加密的儲存區，不提供綁定，實例內自行登入一次。
- `instances.json` 為 `{instances, defaultAccountIDs}`，仍可讀舊版只有陣列的格式。

刪除 Instance 時先送 SIGTERM 並等主程序結束（最多 10 秒，逾時則不刪），否則還在跑的 App 會把資料夾寫回來。只允許處理 `Application Support/AspaceI/Instances/` 的直接子目錄，並移至垃圾桶以保留復原能力；外部路徑一律拒絕。

### 切換帳號

「切換」＝把預設實例（官方 App）換成這個帳號，目前只支援 Codex（寫 `~/.codex/auth.json`，需要完整 tokens）與 Antigravity（寫 `~/.gemini/jetski-standalone-oauth-token`，只有 refresh token 時給過期的 access token 讓官方 App 自己換新）。Claude Desktop、VS Code 的登入存在各自加密的儲存區，只能「設為目前帳號」（僅影響 AspaceI 內的粗體標示）。

流程由 `InstanceManager.switchDefault` 負責：官方 App 在執行時先確認 → SIGTERM 並等到主程序結束（最多 10 秒，逾時則不切換）→ `AccountManager.switchDefaultClient` 寫檔、記錄 `defaultClientAccountIDs`、設為目前帳號 → 重新開啟 App。

`defaultClientAccountIDs`（UserDefaults）記錄哪個帳號正在官方 App 裡；沒有紀錄時視為本機匯入的帳號。這個帳號的影響：
- 每輪同步官方檔案時寫回的是它，不是固定寫回本機帳號（否則切換後會把 B 的 token 寫進 A）。Codex 另比對 id_token 的 email，對不上就不寫。
- 它的 token 交給官方 App 換新，AspaceI 不輪替。
- 啟動時目前帳號（粗體）與它對齊。

刪除帳號需二次確認；刪掉本機匯入的帳號後，啟動時的自動匯入會略過該平台，直到使用者按「讀取這台 Mac」。

App 以 bundle identifier 尋找（`NSWorkspace.urlForApplication(withBundleIdentifier:)`），因為 App 會改名：Codex 現在是 `ChatGPT.app`（`com.openai.codex`）。
