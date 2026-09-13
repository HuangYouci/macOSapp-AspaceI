# 貢獻指南

提交前請執行：

```bash
swift build
swift test
./scripts/build-app.sh
```

不得提交 token、Cookie、登入資料庫或任何真實帳號資料。新增平台整合時，畫面只接收統一的 `Account` 與 `QuotaSnapshot`，登入與網路行為保留在 Service。
