import Foundation

/// 把 Claude Code 與 Codex 記錄檔的單行轉成用量。規則比對自 ccusage（`rust/adapters/claude`、`rust/adapters/codex`）。
enum UsageLineParser {
    /// Claude Code 對話紀錄中帶 `message.usage` 的一行。
    /// 同一則回應每個 content block 各寫一行、續接的對話會把歷史抄進新檔，所以每筆帶去重鍵。
    static func claudeEntry(line: Data, sessionID: String) -> UsageEntry? {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let message = root["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let model = message["model"] as? String, model != "<synthetic>",
              let timestamp = root["timestamp"] as? String, let time = epochSeconds(iso8601: timestamp) else { return nil }
        // 有 5 分鐘／1 小時的細項就以細項為準，沒有就全算 5 分鐘（同 ccusage）。
        let breakdown = usage["cache_creation"] as? [String: Any]
        let write5m = breakdown.map { int($0["ephemeral_5m_input_tokens"]) }
        let write1h = breakdown.map { int($0["ephemeral_1h_input_tokens"]) } ?? 0
        let tokens = TokenCounts(
            input: int(usage["input_tokens"]),
            output: int(usage["output_tokens"]),
            cacheRead: int(usage["cache_read_input_tokens"]),
            cacheWrite: write5m.map { $0 + write1h } ?? int(usage["cache_creation_input_tokens"]),
            cacheWrite1h: write1h
        )
        let messageID = message["id"] as? String ?? ""
        var identity = messageID
        if let requestID = root["requestId"] as? String {
            identity += "|" + requestID
        } else {
            // 沒有 requestId 時以對話區分；訊息編號不是 API 給的（非 msg_ 開頭）就再加上時間。
            identity += "|" + sessionID + (messageID.hasPrefix("msg_") ? "" : "|" + timestamp)
        }
        return UsageEntry(key: hash(identity), time: time, model: model, tokens: tokens)
    }

    /// Codex 對話檔要依序讀：模型寫在 `turn_context`，用量是累計值與本輪值並列的 `token_count` 事件。
    struct CodexState: Equatable, Sendable, Codable {
        var model: String?
        var previousTotal: [Int]?
    }

    /// 回傳這一行產生的用量；不是用量事件、或累計值沒有前進（同一輪重複送出）時回傳 nil。
    static func codexEntry(line: Data, state: inout CodexState) -> UsageEntry? {
        guard let root = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let payload = root["payload"] as? [String: Any] else { return nil }
        let type = root["type"] as? String
        if type == "turn_context" {
            if let model = (payload["model"] as? String) ?? (payload["model_name"] as? String) { state.model = model }
            return nil
        }
        guard type == "event_msg", payload["type"] as? String == "token_count",
              let info = payload["info"] as? [String: Any],
              let timestamp = root["timestamp"] as? String, let time = epochSeconds(iso8601: timestamp) else { return nil }
        let total = (info["total_token_usage"] as? [String: Any]).map(codexFields)
        let last = (info["last_token_usage"] as? [String: Any]).map(codexFields)
        defer { if let total { state.previousTotal = total } }
        if let total, total == state.previousTotal { return nil }
        let delta: [Int]
        if let last {
            delta = last
        } else if let total {
            let previous = state.previousTotal ?? [0, 0, 0, 0]
            delta = zip(total, previous).map { max($0 - $1, 0) }
        } else {
            return nil
        }
        // Codex 的 input 含快取讀取，reasoning 已經算在 output 裡。
        let cached = min(delta[1], delta[0])
        let tokens = TokenCounts(input: delta[0] - cached, output: delta[3], cacheRead: cached, cacheWrite: delta[2])
        guard !tokens.isZero else { return nil }
        return UsageEntry(key: 0, time: time, model: state.model ?? "gpt-5", tokens: tokens)
    }

    /// [input, cached, cacheWrite, output]
    private static func codexFields(_ usage: [String: Any]) -> [Int] {
        [
            int(usage["input_tokens"]),
            int(usage["cached_input_tokens"] ?? usage["cache_read_input_tokens"]),
            int(usage["cache_write_input_tokens"] ?? usage["cache_creation_input_tokens"]),
            int(usage["output_tokens"])
        ]
    }

    private static func int(_ value: Any?) -> Int {
        max((value as? NSNumber)?.intValue ?? 0, 0)
    }

    /// `2026-10-12T06:58:28.123Z` 這種 UTC 時間。`ISO8601DateFormatter` 對幾十萬行太慢，自己算。
    static func epochSeconds(iso8601 text: String) -> Int? {
        let bytes = Array(text.utf8)
        guard bytes.count >= 20, bytes[4] == 45, bytes[7] == 45, bytes[10] == 84, bytes[13] == 58, bytes[16] == 58,
              bytes.last == 90 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for byte in bytes[range] {
                guard byte >= 48, byte <= 57 else { return nil }
                value = value * 10 + Int(byte - 48)
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              let hour = number(11..<13), let minute = number(14..<16), let second = number(17..<19),
              (1...12).contains(month), (1...31).contains(day), hour < 24, minute < 60, second < 61 else { return nil }
        // Howard Hinnant 的 days_from_civil。
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        return days * 86_400 + hour * 3_600 + minute * 60 + second
    }

    /// FNV-1a 64；0 保留給「不參與去重」。
    static func hash(_ text: String) -> UInt64 {
        var value: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01b3
        }
        return value == 0 ? 1 : value
    }
}
