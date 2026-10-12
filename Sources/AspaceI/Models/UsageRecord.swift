import Foundation

/// 一段用量的 token 數。`input` 不含快取（與 ccusage 相同）：開了 prompt caching 之後，
/// 絕大部分送進模型的 token 都算在快取讀寫，混在一起就看不出實際新送了多少。
struct TokenCounts: Equatable, Hashable, Sendable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0

    var cache: Int { cacheRead + cacheWrite }
    var total: Int { input + output + cacheRead + cacheWrite }
    var isZero: Bool { total == 0 }

    static func + (lhs: TokenCounts, rhs: TokenCounts) -> TokenCounts {
        TokenCounts(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite: lhs.cacheWrite + rhs.cacheWrite
        )
    }

    static func += (lhs: inout TokenCounts, rhs: TokenCounts) {
        lhs = lhs + rhs
    }
}

/// 從記錄檔讀出來的一筆用量（Claude 的一則回應、Codex 的一輪）。
struct UsageEntry: Equatable, Sendable {
    /// 跨檔去重用；0 表示這筆不參與去重。
    var key: UInt64
    /// 發生時間，epoch 秒。
    var time: Int
    var model: String
    var tokens: TokenCounts
}

/// 彙總後的一格：某一天、某平台、某模型、某個擁有者的用量。
struct UsageRecord: Equatable, Sendable {
    /// 使用者時區當天 00:00。
    let day: Date
    let platform: PlatformKind
    let model: String
    /// Claude 為平台帳號編號（`Account.accountUUID`），Codex 為 AspaceI 帳號 id；nil 表示無法歸屬。
    let owner: String?
    var tokens: TokenCounts
}
