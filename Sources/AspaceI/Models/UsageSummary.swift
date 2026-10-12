import Foundation

enum UsageRange: String, CaseIterable, Identifiable, Sendable {
    case today, week, month, all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "今日"
        case .week: "7 日"
        case .month: "30 日"
        case .all: "全部"
        }
    }
}

/// 依區間把彙總結果整理成畫面要的表：今日以小時分段，其他區間以日分段。純計算，不碰檔案。
struct UsageSummary: Equatable, Sendable {
    struct Model: Equatable, Identifiable, Sendable {
        let name: String
        let platform: PlatformKind
        let tokens: TokenCounts
        var id: String { name }
    }

    struct Period: Equatable, Identifiable, Sendable {
        let start: Date
        let tokens: TokenCounts
        var id: Date { start }
    }

    let isHourly: Bool
    /// 由舊到新，沒有用量的時段也列出來。
    let periods: [Period]
    let models: [Model]
    let total: TokenCounts

    init(records: [UsageRecord], range: UsageRange, now: Date, calendar: Calendar) {
        let todayStart = calendar.startOfDay(for: now)
        isHourly = range == .today
        let firstDay: Date
        switch range {
        case .today: firstDay = todayStart
        case .week: firstDay = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        case .month: firstDay = calendar.date(byAdding: .day, value: -29, to: todayStart) ?? todayStart
        case .all: firstDay = records.map { calendar.startOfDay(for: $0.hour) }.min() ?? todayStart
        }
        let inRange = records.filter { $0.hour >= firstDay && $0.hour <= now }

        let unit: Calendar.Component = isHourly ? .hour : .day
        var byPeriod: [Date: TokenCounts] = [:]
        var byModel: [String: (PlatformKind, TokenCounts)] = [:]
        for record in inRange {
            let start = isHourly ? record.hour : calendar.startOfDay(for: record.hour)
            byPeriod[start, default: TokenCounts()] += record.tokens
            byModel[record.model, default: (record.platform, TokenCounts())].1 += record.tokens
        }
        var periods: [Period] = []
        var cursor = firstDay
        let last = isHourly ? (calendar.dateInterval(of: .hour, for: now)?.start ?? now) : todayStart
        while cursor <= last {
            periods.append(Period(start: cursor, tokens: byPeriod[cursor] ?? TokenCounts()))
            guard let next = calendar.date(byAdding: unit, value: 1, to: cursor) else { break }
            cursor = next
        }
        self.periods = periods
        models = byModel
            .map { Model(name: $0.key, platform: $0.value.0, tokens: $0.value.1) }
            .sorted { ($0.tokens.total, $1.name) > ($1.tokens.total, $0.name) }
        total = inRange.reduce(TokenCounts()) { $0 + $1.tokens }
    }
}
