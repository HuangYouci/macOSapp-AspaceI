import Foundation

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let windows: [QuotaWindow]
    let fetchedAt: Date
    var identity: String?
    var plan: String?
    /// Antigravity 的原始 tier id，決定要問哪個 cloud code 後端。
    var tierID: String?

    init(windows: [QuotaWindow], fetchedAt: Date, identity: String? = nil, plan: String? = nil, tierID: String? = nil) {
        self.windows = windows
        self.fetchedAt = fetchedAt
        self.identity = identity
        self.plan = plan
        self.tierID = tierID
    }

    /// 主要時窗：menu bar 與緊縮列只取這兩格。
    var primaryWindows: [QuotaWindow] {
        let main = windows.filter { $0.group == nil }
        let source = main.isEmpty ? windows : main
        return [QuotaWindow.Kind.fiveHour, .week, .month].compactMap { kind in
            source.first { $0.kind == kind }
        }
    }
}

struct QuotaWindow: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        case fiveHour, week, month, other

        /// 5h = 段（S）、7d = 週（W）、1m = 月（M）；其他時窗不顯示。
        var shortTitle: String {
            switch self {
            case .fiveHour: String(localized: "QuotaWindowSession", defaultValue: "段", bundle: .module)
            case .week: String(localized: "QuotaWindowWeek", defaultValue: "週", bundle: .module)
            case .month: String(localized: "QuotaWindowMonth", defaultValue: "月", bundle: .module)
            case .other: ""
            }
        }

        static func from(seconds: Double) -> Kind {
            switch seconds {
            case 17_000...19_000: .fiveHour
            case 590_000...620_000: .week
            case 2_400_000...2_700_000: .month
            default: .other
            }
        }
    }

    let id: String
    let title: String
    let remainingPercentage: Int
    let resetsAt: Date?
    var kind: Kind
    var group: String?

    init(id: String, title: String, remainingPercentage: Int, resetsAt: Date?, kind: Kind = .other, group: String? = nil) {
        self.id = id
        self.title = title
        self.remainingPercentage = min(max(remainingPercentage, 0), 100)
        self.resetsAt = resetsAt
        self.kind = kind
        self.group = group
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, remainingPercentage, resetsAt, kind, group
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        remainingPercentage = try container.decode(Int.self, forKey: .remainingPercentage)
        resetsAt = try container.decodeIfPresent(Date.self, forKey: .resetsAt)
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .other
        group = try container.decodeIfPresent(String.self, forKey: .group)
    }
}
