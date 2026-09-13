# AspaceI

AspaceI 是一款 macOS 本機選單列工具，用於集中查看 AI 開發工具帳號、額度與重置時間，並逐步支援多帳號及多 Instance。

## 目前狀態

- macOS 選單列入口
- 可置頂的漂浮額度視窗
- 本機登入狀態唯讀偵測
- 非敏感帳號資料本機保存
- 敏感憑證 Keychain 儲存層
- Codex、Claude 與 GitHub API 額度更新
- 獨立 profile 的多 Instance 建立、啟動與停止

Antigravity 的 `state.vscdb` 可用於隔離 Instance；額度更新需另外匯入包含 `access_token` 的帳號 JSON。其 Cloud Code 個人額度介面不是穩定公開契約，若官方改版可能需要同步更新。

## 開發

需求：macOS 15、Xcode 16 或相容的 Swift 6.2 工具鏈。

```bash
swift build
swift test
swift run AspaceI
```

產生可直接開啟的 App：

```bash
./scripts/build-app.sh
open dist/AspaceI.app
```

建置腳本會進行 ad-hoc codesign，適合本機使用。公開下載若要避免 Gatekeeper 警告，仍需使用 Apple Developer ID 簽署及 notarization。

本專案不會將 token 寫入原始碼、Log、版本控制或一般設定檔。

## 使用方式

1. 從選單列開啟 AspaceI，選擇「匯入本機帳號」。
2. Codex 讀取 `~/.codex/auth.json`；GitHub 透過官方 `gh auth token` 讀取 Keychain；Claude 讀取 Claude Code credentials；Antigravity 偵測其 `state.vscdb`。
3. 其他帳號可在「帳號與額度」選擇「從檔案加入」。敏感 JSON／YAML 會立即存入 AspaceI Keychain。
4. 「設為目前帳號」只改 AspaceI 顯示；「套用至官方客戶端」會寫入官方預設 profile，操作前請關閉該客戶端。
5. 建立 Instance 時選擇平台、帳號與官方可執行檔。每個 Instance 使用獨立 profile。

GitHub 不覆蓋系統 Keychain；綁定 Instance 時以 `GH_TOKEN` 注入該子程序。Antigravity 額度需匯入含 `access_token` 的 JSON，`state.vscdb` 本身只作為隔離登入快照。
