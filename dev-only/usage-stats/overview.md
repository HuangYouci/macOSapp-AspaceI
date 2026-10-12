# 本機用量統計

最後更新日期：2026-10-12

對應功能／commit：用量費用（API 牌價估算）與 CSV 匯出；popup「用量」分頁（今日每小時、7 日／30 日／全部每日、模型）；用量歷史由 AspaceI 自己保存；不分帳號

## 資料來源

只讀這台 Mac 上的記錄檔，不連網。解析規則比對自 ccusage（`ccusage/ccusage` 的 `rust/adapters/claude`、`rust/adapters/codex`）。

| 平台 | 位置 | 用量所在 |
| :--- | :--- | :--- |
| Claude Code | `~/.claude/projects/**/*.jsonl`、`~/.config/claude/projects`；所有 Claude 桌面實例共用 `~/.claude` | 帶 `message.usage` 的行 |
| Codex | `~/.codex` 與各 Codex 實例的 `CODEX_HOME`，底下的 `sessions/`、`archived_sessions/` | `event_msg` / `token_count`；模型取自前面的 `turn_context` |

Copilot 與 Antigravity 未支援：這台 Mac 的 Copilot 沒有開 OTel 匯出，Antigravity 是 protobuf 包在 SQLite 裡，等有需要再做。

## 計數規則

- **輸入不含快取**（同 ccusage）：開 prompt caching 後送進模型的 token 絕大部分是快取讀寫（2026-10-12 這台 Mac：輸入 125 萬、快取 594 億），混在一起看不出實際新送了多少。畫面上分成輸入、輸出、快取（讀＋寫）三欄。
- **Claude 去重**：鍵為 `message.id` + `requestId`（沒有 requestId 時加對話編號，非 `msg_` 開頭再加時間）。同一則回應逐個 content block 各寫一行，後面的 output 才完整，所以重複時留 token 多的那筆。續接、分叉的對話會把歷史抄進新檔，跨檔也要去重——只做單檔去重會多算 5～6%（實測）。`<synthetic>` 模型略過。
- **Codex**：用 `last_token_usage`（本輪值）；`total_token_usage` 沒前進代表同一輪重複送出，略過；沒有本輪值就拿累計值相減。`input_tokens` 含快取讀取要扣掉，reasoning 已含在 output。2026-10-12 檢查這台 Mac 的分叉子代理檔，用量從零起算，沒有重播父對話的事件，所以沒有實作 ccusage 的重播偵測。
- **日期**：以使用者目前時區切日。快取存的是事件時間（epoch 秒），換時區不必重掃。

## 費用

畫面上的費用是「同樣用量照 API 牌價要多少錢」，不是訂閱實際付的金額。

- **價格來源**：LiteLLM 的公開價格表 `model_prices_and_context_window.json`，與 ccusage 同源。由 `dev-only/usage-stats/update-pricing.py` 抓下來、只留 `claude-*` 與 `gpt-*`，產生 `Sources/AspaceI/Resources/Pricing/model-prices.json` 打包進 App；設定頁顯示來源與抓取日期。App 不在執行時連網抓價格。新模型上市或調價時重跑腳本再建置。只有 `chatgpt/` 前綴的模型（例如 `gpt-5.3-codex-spark`）若沒有單價就不估，畫面顯示「–」。
- **權威性**：LiteLLM 是社群維護的表，數字抄自各家官方價目頁；真正的權威只有 Anthropic／OpenAI 的價目頁與帳單。這裡能保證的是算法與 ccusage 一致。
- **公式**（同 ccusage）：輸入×輸入價 + 輸出×輸出價 + 快取讀取×讀取價 + 5 分鐘快取寫入×寫入價 + 1 小時快取寫入×1 小時寫入價。快取沒有單價時，寫入以輸入×1.25、讀取以輸入×0.1、1 小時寫入以輸入×2 計。模型名稱帶日期尾碼（`-20251001`）查不到時去掉尾碼再查。
- **長上下文**：價格表有 `*_above_<N>k_tokens` 的模型（目前是 GPT 系列的 272k），單次請求的輸入＋快取讀寫超過門檻時，整次改用較高的價格。Codex 的 priority／flex 服務層級沒有記錄，一律以標準價計。
- **1 小時快取**：Claude Code 目前的快取寫入全是 1 小時的（2026-10-12 抽查最近 40 個對話：4.24 億 token 全在 `ephemeral_1h_input_tokens`），1 小時的寫入價比 5 分鐘的高 60%，所以要分開記。為此解析版本升到 2（`UsageFileRecord.currentRevision`），記錄檔還在的會整個重讀。
- **驗證**：2026-10-12 以 ccusage 20.0.26 離線模式對帳 10/6～10/12。claude-opus-5-5 與 gpt-6-luna 的每日費用逐一相同；ccusage 這版內建的價格表沒有 claude-sonnet-5-5，把它算成 $0，所以有 sonnet 的日子 ccusage 較低。

## 匯出

設定頁「用量 → 匯出用量」輸出 CSV：每小時、每個模型一列，欄位為 `hour`（帶時區位移）、`platform`、`model`、輸入／輸出／快取讀取／快取寫入／其中 1 小時快取寫入的 token，以及 `cost_usd`（查不到價格時留空）。

## 不分帳號（2026-10-12 決策）

記錄檔幾乎不帶帳號，ccusage 也完全不分帳號。曾嘗試從各 Claude 桌面實例的 `claude-code-sessions/<帳號編號>/…/local_*.json`（`cliSessionId` 對到記錄檔）對應，但對話封存或刪除後只剩不含 `cliSessionId` 的墓碑，首次掃描時約三分之二的歷史用量對不到帳號；Codex 記錄檔則完全不帶帳號。負責人決定既然分不準就不分，只看全部與各模型。

## 正確性

2026-10-12 以 ccusage 20.0.26（`daily --offline --json`）對帳 10/6～10/12：七天的輸入、輸出、快取讀寫逐日一致（ccusage v20 預設也是 Claude + Codex 合計）。

## 用量歷史與效能

- `~/Library/Application Support/AspaceI/usage-history.plist`（binary plist，`UsageHistory`）：AspaceI 自己保存的用量歷史，每個記錄檔讀到的位置與每筆用量（平行陣列）。負責人會定期刪對話紀錄，所以記錄檔刪掉後這裡的用量保留，這份檔案不是可以丟掉重建的快取。每 5 分鐘掃一次（popup 沒開也掃），趁記錄檔還在時讀進來。
- 檔案只會往後寫，變大時從上次的位置接著讀；變小則整個重讀。
- 讀不出來（損毀、版本不同）時不覆寫，原檔改名為 `usage-history.plist.unreadable-<時間>` 保留，再從現有記錄檔重新累積。第一版的檔名 `usage-cache.plist` 會在第一次讀取時改名。
- 彙總以小時為單位（使用者時區），「今日」看每小時，其他區間看每日。
- 首次掃描要讀十幾 GB。只有含關鍵字的行才解析 JSON；找行用 `memchr` 找關鍵字裡最少見的位元組再比對，並對 mmap 下 `MADV_SEQUENTIAL`。Darwin 的 `memmem` 每秒只有兩三百 MB，沒有循序提示時 mmap 逐頁缺頁，7.5GB 要 40 秒（2026-10-12 實測）。之後每輪只讀新增的部分，約數秒。
