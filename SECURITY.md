# 安全政策

請勿在公開 Issue 張貼 token、Cookie、登入資料庫、`auth.json` 或 Keychain 匯出內容。

若發現可能導致憑證外洩的問題，請改以 GitHub Security Advisory 私下回報。AspaceI 不會要求使用者提交密碼，也不會把憑證傳送至 AspaceI 自建伺服器。

## 本機資料邊界

- Token 與 refresh token 儲存在 macOS Keychain，不寫入 repository 或一般設定檔。
- 帳號名稱、平台、額度快取與重置時間儲存在使用者的 Application Support 目錄。
- 額度查詢只連線至對應服務供應商的 API。
- 公開原始碼不包含使用者的 Keychain 內容；fork、Issue、Log 與診斷檔仍不得附上登入資料。

安裝非本 repository 建置的版本前，請先檢查其原始碼與發布者。任何取得 Keychain 使用權限的修改版 App 都可能讀取它自己保存的憑證。
