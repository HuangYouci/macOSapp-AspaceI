import Foundation

enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case week, month, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: "7 天"
        case .month: "30 天"
        case .all: "全部"
        }
    }
}

/// 用量的擁有者：某平台的某個帳號，`owner` 為 nil 表示記錄檔看不出是誰。
struct UsageOwnerKey: Hashable, Sendable {
    let platform: PlatformKind
    let owner: String?
}

/// 依區間與篩選把彙總結果整理成畫面要的三張表。純計算，不碰檔案。
struct UsageSummary: Equatable, Sendable {
    struct Row: Equatable, Identifiable, Sendable {
        let id: String
        let title: String
        let platform: PlatformKind?
        let tokens: TokenCounts
    }

    struct Day: Equatable, Identifiable, Sendable {
        let day: Date
        let tokens: TokenCounts
        var id: Date { day }
    }

    let days: [Day]
    let models: [Row]
    let owners: [Row]
    let total: TokenCounts

    /// `filter` 只影響每日與模型；帳號表固定列出區間內所有擁有者，才能點別的帳號切換。
    init(records: [UsageRecord], range: UsageRange, filter: UsageOwnerKey?, accounts: [Account], today: Date, calendar: Calendar) {
        let todayStart = calendar.startOfDay(for: today)
        let firstDay: Date
        switch range {
        case .week: firstDay = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        case .month: firstDay = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        case .all: firstDay = records.map(\.day).min() ?? todayStart
        }
        let inRange = records.filter { $0.day >= firstDay && $0.day <= todayStart }
        let filtered = filter.map { key in inRange.filter { UsageOwnerKey(platform: $0.platform, owner: $0.owner) == key } } ?? inRange

        var byDay: [Date: TokenCounts] = [:]
        var byModel: [String: (PlatformKind, TokenCounts)] = [:]
        for record in filtered {
            byDay[record.day, default: TokenCounts()] += record.tokens
            byModel[record.model, default: (record.platform, TokenCounts())].1 += record.tokens
        }
        var days: [Day] = []
        var cursor = firstDay
        while cursor <= todayStart {
            days.append(Day(day: cursor, tokens: byDay[cursor] ?? TokenCounts()))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.days = days
        models = byModel
            .map { Row(id: $0.key, title: $0.key, platform: $0.value.0, tokens: $0.value.1) }
            .sorted { ($0.tokens.total, $1.title) > ($1.tokens.total, $0.title) }
        total = filtered.reduce(TokenCounts()) { $0 + $1.tokens }

        var byOwner: [UsageOwnerKey: TokenCounts] = [:]
        for record in inRange {
            byOwner[UsageOwnerKey(platform: record.platform, owner: record.owner), default: TokenCounts()] += record.tokens
        }
        owners = byOwner
            .map { key, tokens in
                Row(id: Self.rowID(key), title: Self.title(for: key, accounts: accounts), platform: key.platform, tokens: tokens)
            }
            .sorted { ($0.tokens.total, $1.title) > ($1.tokens.total, $0.title) }
    }

    static func rowID(_ key: UsageOwnerKey) -> String {
        "\(key.platform.rawValue):\(key.owner ?? "")"
    }

    /// Claude 的擁有者是平台帳號編號，Codex 是 AspaceI 帳號 id；對不到 AspaceI 裡的帳號就顯示編號前 8 碼。
    static func title(for key: UsageOwnerKey, accounts: [Account]) -> String {
        guard let owner = key.owner else { return "未歸屬" }
        let account = accounts.first { account in
            guard account.platform == key.platform else { return false }
            return key.platform == .claude ? account.accountUUID?.lowercased() == owner : account.id.uuidString == owner
        }
        return account?.label ?? String(owner.prefix(8))
    }
}
