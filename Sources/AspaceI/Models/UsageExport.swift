import Foundation

/// 用量匯出成 CSV：每小時、每個模型一列，時間帶時區位移，試算表可直接開。
enum UsageExport {
    static let header = "hour,platform,model,input_tokens,output_tokens,cache_read_tokens,cache_write_tokens,cache_write_1h_tokens,cost_usd"

    static func csv(_ records: [UsageRecord], timeZone: TimeZone) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = timeZone
        formatter.formatOptions = [.withInternetDateTime]
        let rows = records.sorted { ($0.hour, $0.platform.rawValue, $0.model) < ($1.hour, $1.platform.rawValue, $1.model) }.map { record in
            [
                formatter.string(from: record.hour),
                record.platform.rawValue,
                escape(record.model),
                "\(record.tokens.input)",
                "\(record.tokens.output)",
                "\(record.tokens.cacheRead)",
                "\(record.tokens.cacheWrite)",
                "\(record.tokens.cacheWrite1h)",
                record.cost.map { String(format: "%.6f", $0) } ?? ""
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func escape(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
