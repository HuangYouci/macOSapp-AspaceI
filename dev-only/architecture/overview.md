# AspaceI 架構概覽

最後更新日期：2026-09-13

對應功能／commit：AspaceI 26.9.13 GUI 與常駐模式

## 邊界

AspaceI 採本機優先架構。畫面只呈現注入的帳號及額度狀態，不直接存取登入檔案、Keychain 或遠端服務。

## 資料流

1. `LocalAccountDiscoveryService` 唯讀檢查官方客戶端的登入儲存是否存在。
2. `CredentialImportService` 讀取既有憑證後立即交給 `KeychainService`，不輸出內容。
3. `QuotaService` 在記憶體內取得 token 並轉換各平台回應。
4. `AccountManager` 協調匯入、額度與非敏感資料保存。
5. `MenuBarContentView` 與 `FloatingQuotaView` 僅接收 `AccountManager` 提供的資料。

額度每五分鐘在背景更新；失敗時保留最後一次成功快取並於帳號列顯示狀態。

## App 生命週期與 GUI

- App 採 accessory activation policy，不顯示 Dock 圖示。
- 關閉主視窗只關閉 GUI，選單列與背景額度更新持續運作。
- 使用者只能從選單列的「結束 AspaceI」真正終止 App。
- 主 GUI 統整帳號、Instance、設定與關於頁；選單列保留快速額度與常用動作。
- 登入時開啟採用系統 `SMAppService.mainApp`，不自行維護 LaunchAgent。

## 機密資料

- Token 與 refresh token 只存入 macOS Keychain。
- 一般 JSON 僅保存帳號識別資訊、平台、方案、額度快取及重置時間。
- Log 不得包含 token、Authorization header、Cookie 或原始登入檔案內容。
- GitHub 使用官方 `gh auth token` 從系統 Keychain 取值，轉存時只寫入 AspaceI Keychain；啟動綁定 Instance 時以環境變數注入。

## 多 Instance

每個 Instance 使用獨立 profile 目錄。啟動前才將指定帳號憑證投影至該 profile，運作期間不做背景覆寫。Codex、Claude 與 GitHub CLI 使用環境變數隔離；Antigravity 使用獨立 user-data 目錄。

刪除 Instance 時只允許處理 `Application Support/AspaceI/Instances/` 的直接子目錄，並移至垃圾桶以保留復原能力；外部路徑一律拒絕。

「設為目前帳號」只改變 AspaceI 的選擇；「套用至官方客戶端」才會以原子寫入將憑證投影至官方預設 profile。套用前應先關閉對應官方客戶端，避免官方程序同時輪替憑證。
