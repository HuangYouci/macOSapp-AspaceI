# AspaceI

AspaceI 是 macOS 選單列工具，集中管理 GitHub Copilot、Claude、Codex、Antigravity 的多個帳號：看額度、切換帳號、用不同帳號同時開多個 App 實例。

- 選單列最多同時顯示 3 個帳號的額度：`{icon} abc 12% 40% | …`
- 不建立主視窗、不顯示 Dock 圖示
- 憑證只存在這台 Mac 的 Keychain，沒有 AspaceI 自己的伺服器

目前版本：26.9.13　作者：Huang Youci

## 功能

### 額度

每個服務一張卡片，欄位依服務實際提供的額度週期顯示：

| 服務 | 段（5 小時） | 週 | 月 | 方案 |
| --- | :---: | :---: | :---: | --- |
| Codex | ● | ● | | Plus / Pro 5x / Pro 20x … |
| Claude | ● | ● | | Pro / Max 5x / Max 20x … |
| Antigravity | ● | ● | | Free / Pro / Ultra |
| GitHub Copilot | | | ● | Free / Pro / Pro+ / Business … |

- 每 5 分鐘自動更新，粗體為目前使用中的帳號。
- Codex Pro 帳號若只回傳週額度，就只顯示週欄位。
- Codex 的方案代碼 `pro` 無法區分 5x／20x，會顯示為 Pro 20x；只有 `prolite` 會顯示 Pro 5x。

### 帳號

**加入帳號**有三種方式：

| 方式 | Codex | Claude | Antigravity | GitHub Copilot |
| --- | --- | --- | --- | --- |
| 瀏覽器登入 | OpenAI OAuth | Claude OAuth（貼回授權碼） | Google OAuth | GitHub 裝置碼 |
| 讀取這台 Mac | `~/.codex/auth.json` | Claude Code 的 Keychain 或 `~/.claude/.credentials.json` | `~/.gemini/jetski-standalone-oauth-token` | `gh auth token` 或 `~/.config/gh/hosts.yml` |
| 貼上或拖入 | `auth.json` 內容 | `.credentials.json` 內容、`sk-ant-oat…` | refresh token（`1//…`）或 token 檔 | `gho_…` / `ghu_…` token |

貼上的內容會自動辨識服務與格式。

**切換帳號**（⋮ 選單）：

- **Codex、Antigravity**：寫入官方 App 讀取的登入檔，App 開著時會先確認、關閉，再以新帳號重新開啟。
- **Claude、GitHub Copilot**：官方 App 的登入存在加密儲存，無法由外部寫入，只能在 AspaceI 內標記為目前帳號。

**Token 保活**：Codex、Claude 的 token 會在過期前自動換新；正在官方 App 中使用的帳號交由官方 App 換新，避免互相把對方登出。

### 實例

依 VS Code、Antigravity、Claude、Codex 分組。每組第一個是預設實例（就是平常打開的 App），可另外新增實例，各自使用獨立的資料夾與帳號，同時執行互不干擾。

實例資料位於 `~/Library/Application Support/AspaceI/Instances/`。

### 設定

- 登入時開啟
- 勾選顯示在選單列的帳號（最多 3 個）
- 匯入／匯出帳號

## 安裝

目前不提供預先建置的下載檔，請自行從原始碼建置。

需求：macOS 15 以上、Xcode 16 以上（Swift 6.2）。

```bash
git clone https://github.com/huangyouci/macOSapp-AspaceI.git
cd macOSapp-AspaceI
./scripts/build-app.sh
cp -R dist/AspaceI.app /Applications/
open /Applications/AspaceI.app
```

### 簽署與 Keychain 授權

`build-app.sh` 會自動挑選 Keychain 中第一個 Apple Development 或 Developer ID 憑證簽署；找不到時改用 ad-hoc 簽署。

- **有開發者憑證**（免費 Apple ID 登入 Xcode 即可產生）：簽署身分固定，重新建置後 Keychain 按一次「永遠允許」就不會再問。
- **ad-hoc 簽署**：每次重新建置都視為不同的 App，macOS 會再次詢問 Keychain 授權。

### 更新

```bash
git pull
./scripts/build-app.sh
cp -R dist/AspaceI.app /Applications/
```

帳號與實例資料不在 App 內，更新不會遺失。

## 從 Cockpit Tools 搬家

1. 在 Cockpit Tools 匯出帳號 JSON。
2. AspaceI「設定 → 匯入帳號 → 選擇檔案…」選那個檔案。

支援 Codex、Claude（OAuth 與 setup token）、Antigravity、GitHub Copilot 帳號。Cockpit 的 Claude Desktop 帳號是加密保存且不會被匯出，需要在 AspaceI 重新以瀏覽器登入。

## 匯入匯出格式

匯出檔為 AspaceI 自有格式（`aspacei.accounts` v1），**內含可直接登入的 token**，檔案權限為 `0600`。請勿上傳到雲端硬碟、Issue 或聊天室；用完建議刪除。

## 資料存放位置

| 資料 | 位置 |
| --- | --- |
| Token、refresh token | Keychain：`com.huangyouci.AspaceI` / `credentials-vault` |
| 帳號清單、額度快取 | `~/Library/Application Support/AspaceI/` |
| 實例設定與資料夾 | `~/Library/Application Support/AspaceI/` |

完整移除：結束 App、刪除 `/Applications/AspaceI.app` 與上述資料夾，並在「鑰匙圈存取」刪除 `com.huangyouci.AspaceI` 項目。

## 安全與限制

- 網路連線只會連往各服務供應商（OpenAI、Anthropic、Google、GitHub）。
- 程式碼中的 OAuth client ID／secret 是各官方桌面與命令列工具公開內建的值，不是個人憑證；Google 對「已安裝應用程式」類型的 secret 不視為機密。
- 額度與登入使用的是官方工具內部介面，並非公開 API，供應商改版時可能失效，也可能不符合其服務條款，請自行評估。
- 本專案與 OpenAI、Anthropic、Google、GitHub 無任何關係。

回報安全問題請見 [SECURITY.md](SECURITY.md)，請勿在 Issue 中貼出 token 或 `auth.json`。

## 開發

```bash
swift build
swift test
swift run AspaceI
```

架構與憑證處理細節見 `dev-only/`。貢獻方式見 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 授權

[MIT](LICENSE)

- [隱私政策](https://huangyouci.com/privacy)
- [使用條款](https://huangyouci.com/terms)
