import Foundation

/// 依 API 牌價估算用量的美元。價格表打包在 App 內（`Resources/Pricing/model-prices.json`），
/// 由 `dev-only/usage-stats/update-pricing.py` 從 LiteLLM 的公開價格表產生，與 ccusage 同源。
/// 訂閱方案實際付的是月費，這裡算的是「同樣用量照 API 計價要多少」。
struct UsagePricing: Sendable {
    struct Price: Codable, Equatable, Sendable {
        var input: Double
        var output: Double
        var cacheRead: Double?
        var cacheWrite: Double?
        var cacheWrite1h: Double?
        /// 單次請求的輸入（含快取）超過這個數，整次改用 `*Above` 的價格。
        var threshold: Int?
        var inputAbove: Double?
        var outputAbove: Double?
        var cacheReadAbove: Double?
        var cacheWriteAbove: Double?
    }

    struct Table: Codable, Equatable, Sendable {
        var source: String
        var fetchedAt: String
        var models: [String: Price]
    }

    let table: Table

    static let bundled: UsagePricing = {
        guard let url = Bundle.module.url(forResource: "model-prices", withExtension: "json", subdirectory: "Pricing"),
              let data = try? Data(contentsOf: url),
              let table = try? JSONDecoder().decode(Table.self, from: data) else {
            return UsagePricing(table: Table(source: "", fetchedAt: "", models: [:]))
        }
        return UsagePricing(table: table)
    }()

    /// 先找完整名稱，再去掉日期尾碼（`claude-haiku-4-5-20251001` → `claude-haiku-4-5`）。
    func price(for model: String) -> Price? {
        if let price = table.models[model] { return price }
        if let range = model.range(of: #"-\d{8}$"#, options: .regularExpression) {
            return table.models[String(model[..<range.lowerBound])]
        }
        return nil
    }

    /// 公式同 ccusage：快取沒有單價時，寫入以輸入 ×1.25、讀取以 ×0.1 計；1 小時快取沒有單價時以輸入 ×2 計。
    func cost(model: String, tokens: TokenCounts) -> Double? {
        guard let price = price(for: model) else { return nil }
        let promptTokens = tokens.input + tokens.cacheRead + tokens.cacheWrite
        let above = price.threshold.map { promptTokens > $0 } ?? false
        let input = above ? price.inputAbove ?? price.input : price.input
        let output = above ? price.outputAbove ?? price.output : price.output
        let cacheRead = (above ? price.cacheReadAbove : nil) ?? price.cacheRead ?? input * 0.1
        let cacheWrite = (above ? price.cacheWriteAbove : nil) ?? price.cacheWrite ?? input * 1.25
        let cacheWrite1h = price.cacheWrite1h ?? input * 2
        let write5m = tokens.cacheWrite - tokens.cacheWrite1h
        return Double(tokens.input) * input
            + Double(tokens.output) * output
            + Double(tokens.cacheRead) * cacheRead
            + Double(write5m) * cacheWrite
            + Double(tokens.cacheWrite1h) * cacheWrite1h
    }
}
