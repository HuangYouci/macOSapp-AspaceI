# AspaceI 架構概覽

最後更新日期：2026-09-13

## 邊界

AspaceI 採本機優先架構。畫面只呈現注入的帳號及額度狀態，不直接存取登入檔案、Keychain 或遠端服務。

## 資料流

1. `LocalAccountDiscoveryService` 唯讀檢查官方客戶端的登入儲存是否存在。
2. `CredentialImportService` 讀取既有憑證後立即交給 `KeychainService`，不輸出內容。
3. `QuotaService` 在記憶體內取得 token 並轉換各平台回應。
4. `AccountManager` 協調匯入、額度與非敏感資料保存。
5. `MenuBarContentView` 與 `FloatingQuotaView` 僅接收 `AccountManager` 提供的資料。

額度每五分鐘在背景更新；失敗時保留最後一次成功快取並於帳號列顯示狀態。

## 機密資料

- Token 與 refresh token 只存入 macOS Keychain。
- 一般 JSON 僅保存帳號識別資訊、平台、方案、額度快取及重置時間。
- Log 不得包含 token、Authorization header、Cookie 或原始登入檔案內容。

## 多 Instance

每個 Instance 使用獨立 profile 目錄。啟動前才將指定帳號憑證投影至該 profile，運作期間不做背景覆寫。Codex 與 Claude 使用環境變數隔離；Antigravity 與 GitHub Copilot 使用獨立 user-data 目錄。
