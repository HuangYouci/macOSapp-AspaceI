# AspaceI 架構概覽

最後更新日期：2026-09-13

## 邊界

AspaceI 採本機優先架構。畫面只呈現注入的帳號及額度狀態，不直接存取登入檔案、Keychain 或遠端服務。

## 資料流

1. `LocalAccountDiscoveryService` 唯讀檢查官方客戶端的登入儲存是否存在。
2. `AccountManager` 協調偵測結果及非敏感資料保存。
3. 後續各平台 Service 負責驗證憑證與轉換統一的 `QuotaSnapshot`。
4. `MenuBarContentView` 與 `FloatingQuotaView` 僅接收 `AccountManager` 提供的資料。

## 機密資料

- Token 與 refresh token 只存入 macOS Keychain。
- 一般 JSON 僅保存帳號識別資訊、平台、方案、額度快取及重置時間。
- Log 不得包含 token、Authorization header、Cookie 或原始登入檔案內容。

## 多 Instance

後續每個 Instance 使用獨立 profile 目錄。啟動前才將指定帳號憑證投影至該 profile，運作期間禁止背景覆寫，並使用跨程序鎖避免 token rotation 競爭。
