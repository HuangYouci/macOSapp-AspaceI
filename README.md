# AspaceI

AspaceI 是一款 macOS 本機選單列工具，用於集中查看 AI 開發工具帳號、額度與重置時間，並逐步支援多帳號及多 Instance。

## 目前狀態

- macOS 選單列入口
- 可置頂的漂浮額度視窗
- 本機登入狀態唯讀偵測
- 非敏感帳號資料本機保存
- 敏感憑證 Keychain 儲存層
- Codex、Claude 與 GitHub Copilot 額度更新
- 獨立 profile 的多 Instance 建立、啟動與停止

Antigravity 尚無穩定公開的個人額度介面；AspaceI 會保留登入狀態並顯示不可用，不會偽造額度。

## 開發

需求：macOS 15、Xcode 16 或相容的 Swift 6.2 工具鏈。

```bash
swift build
swift test
swift run AspaceI
```

本專案不會將 token 寫入原始碼、Log、版本控制或一般設定檔。
