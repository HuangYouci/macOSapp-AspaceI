# 本機憑證匯入

最後更新日期：2026-09-13

對應功能／commit：四平台自動匯入、Antigravity refresh token 換發、帳號去重

## 參考與決策

參考 `jlcodes99/cockpit-tools` 的公開實作確認官方儲存位置與資料結構。

- Codex：先讀 `~/.codex/auth.json`，不存在時讀取 `Codex Auth` Keychain 項目。
- Claude：先讀取 `Claude Code-credentials` Keychain 項目，再回退至 `~/.claude/.credentials.json`。
- GitHub：透過官方 `gh auth token` 取得目前 GitHub CLI token，再回退至 `~/.config/gh/hosts.yml`。
- Antigravity：先讀新版獨立 App 的 `~/.gemini/jetski-standalone-oauth-token`（JSON，含 `token.refresh_token`），不存在時唯讀查詢 Antigravity IDE 的 `state.vscdb` 的 `antigravityUnifiedStateSync.oauthToken`，解析 protobuf 取得 refresh token。

每個平台只保留一個「本機匯入」帳號（`Account.origin == .local`），重新匯入時覆寫同一筆；手動加入與檔案匯入不參與去重。舊資料沒有 `origin` 時依 `sourcePath` 推斷，載入時收斂重複的本機帳號並刪除多餘的 Keychain 項目。

## 安全邊界

匯入資料只在記憶體短暫存在，隨即寫入 AspaceI Keychain。一般帳號資料只保存 Keychain reference，不保存 token。外部 Keychain 項目可能觸發 macOS 權限提示；拒絕後視為未找到，不嘗試繞過。

## Antigravity 換發 access token（2026-09-13 決策變更）

本機只保存 refresh token，access token 約一小時失效，不換發就無法查額度。原本決定不使用 Antigravity 內建的 OAuth client；為了讓額度可用，改為與 cockpit-tools、opencode-antigravity-auth 相同，使用 Antigravity 桌面 App 隨附的 installed-app OAuth client 向 `oauth2.googleapis.com/token` 換發。此 client secret 屬於隨 App 散佈的公開值（Google installed-app 流程不視為機密），並非使用者憑證；若日後 Google 撤銷或更換，額度會回報「憑證已失效」。

OAuth 登入（見 `architecture/overview.md`「加入帳號」）沿用同一組 client；Codex、Claude、GitHub 的 client 也是官方客戶端隨附的公開值，集中在 `OAuthClient`。

## Keychain service

Bundle ID 為 `com.huangyouci.AspaceI`，Keychain service 同名，所有憑證存在同一個 `credentials-vault` 項目。舊版寫在 `app.aspacei.credentials` 或同 service 下每帳號一個的項目，在第一次讀取時併入 vault 並刪除舊項目。

## 各平台憑證格式

每家官方客戶端的憑證 JSON 都不同，AspaceI 存進 Keychain 的就是官方原生格式，方便直接投影回去：

| 平台 | 官方位置 | 形狀 |
| :--- | :--- | :--- |
| Codex | `~/.codex/auth.json` | `{tokens: {id_token, access_token, refresh_token, account_id}, last_refresh}` |
| Claude Code | Keychain `Claude Code-credentials` 或 `~/.claude/.credentials.json` | `{claudeAiOauth: {accessToken, refreshToken, expiresAt(ms), scopes}}` |
| Antigravity | `~/.gemini/jetski-standalone-oauth-token` | `{auth_method, token: {access_token, refresh_token, token_type, expiry}}` |
| GitHub | `gh auth token` 或 `~/.config/gh/hosts.yml` | AspaceI 包成 `{access_token}` |

cockpit-tools 以「Claude Desktop 登入」加入的帳號（檔名 `claude_desktop_*`，`auth_mode = desktop_oauth`）存的是 Claude Desktop 的網頁 session，不是 Claude Code OAuth token，而且 cockpit 匯出時會排除這類帳號，因此無法匯入 AspaceI；需要在 AspaceI 以瀏覽器登入 Claude。`claude setup-token` 產生的 token 只有 inference 權限，額度 API 可能拒絕，此時顯示「沒有讀取額度的權限」。

cockpit-tools 的匯出檔是它自己的帳號紀錄，把上述憑證包在不同欄位：Antigravity `{email, token: {access_token, refresh_token, expiry_timestamp, project_id}}`、Codex `{email, tokens: {...}}`、Claude `{email, auth_mode, claude_credentials_raw: {claudeAiOauth}}`（`setup_token` 模式則在 `api_key`）、GitHub `{github_login, github_access_token, copilot_token}`。`AccountTransferService.decodeForeign` 依這些欄位辨識平台並取出原生憑證。

## 手動匯入可接受的內容

| 平台 | 檔案 | 單一 token |
| :--- | :--- | :--- |
| Codex | `~/.codex/auth.json` 全文 | ChatGPT access token（JWT，含 `https://api.openai.com/auth` claim）；只有 access token 時無法換新，約 10 天後失效 |
| Claude | `.credentials.json` 全文 | `claude setup-token` 產生的 `sk-ant-oat…`，存成 `{accessToken}` |
| Antigravity | `~/.gemini/jetski-standalone-oauth-token` 全文，或 IDE 的 `state.vscdb` | `1//…` refresh token 存成 `{refresh_token}`；`ya29.…` access token 約一小時失效 |
| GitHub | `~/.config/gh/hosts.yml` 全文（原文保存） | `gh auth token` 輸出的 `gho_…` 等，存成 `{access_token}` |

另外接受 AspaceI 帳號備份檔與 cockpit-tools 匯出的帳號陣列（見上節）。
