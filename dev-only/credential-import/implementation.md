# 本機憑證匯入

最後更新日期：2026-09-13

對應功能／commit：四平台自動匯入與手動加入

## 參考與決策

參考 `jlcodes99/cockpit-tools` 的公開實作確認官方儲存位置與資料結構，但不複製其 OAuth client secret。

- Codex：先讀 `~/.codex/auth.json`，不存在時讀取 `Codex Auth` Keychain 項目。
- Claude：先讀取 `Claude Code-credentials` Keychain 項目，再回退至 `~/.claude/.credentials.json`。
- GitHub：透過官方 `gh auth token` 取得目前 GitHub CLI token，再回退至 `~/.config/gh/hosts.yml`。
- Antigravity：唯讀查詢 `state.vscdb` 的 `antigravityUnifiedStateSync.oauthToken`，解析 protobuf 取得 refresh token。

## 安全邊界

匯入資料只在記憶體短暫存在，隨即寫入 AspaceI Keychain。一般帳號資料只保存 Keychain reference，不保存 token。外部 Keychain 項目可能觸發 macOS 權限提示；拒絕後視為未找到，不嘗試繞過。

Antigravity 的本機資料只提供 refresh token。AspaceI 不使用其他專案內建的 OAuth client secret，因此在取得可合法使用的官方 client 設定前，不會用該 refresh token 換發 access token。
