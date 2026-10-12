import Foundation

/// menu bar 每個帳號要顯示哪幾個時窗的剩餘額度。
enum MenuBarQuotaMode: String, CaseIterable, Identifiable, Sendable {
    case session
    case week
    case month
    case sessionAndWeek
    case lowest

    static let defaultValue: MenuBarQuotaMode = .sessionAndWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session: QuotaWindow.Kind.fiveHour.shortTitle
        case .week: QuotaWindow.Kind.week.shortTitle
        case .month: QuotaWindow.Kind.month.shortTitle
        case .sessionAndWeek: "\(QuotaWindow.Kind.fiveHour.shortTitle)+\(QuotaWindow.Kind.week.shortTitle)"
        case .lowest: String(localized: "MenuBarQuotaLowest", defaultValue: "最少", bundle: .module)
        }
    }

    /// 依序要顯示的時窗；`lowest` 不是固定時窗，回傳空陣列由呼叫端另外處理。
    var kinds: [QuotaWindow.Kind] {
        switch self {
        case .session: [.fiveHour]
        case .week: [.week]
        case .month: [.month]
        case .sessionAndWeek: [.fiveHour, .week]
        case .lowest: []
        }
    }
}

struct MenuBarQuotaItem: Equatable, Identifiable, Sendable {
    let id: UUID
    let platform: PlatformKind
    let name: String
    let percentages: [String]

    /// 依使用者選取順序組出 menu bar 項目；已刪除的帳號直接略過，數量不設上限。
    /// 短名稱在所有帳號之間比（不只選到的），同一個帳號在 menu bar 與實例圖示上永遠是同一個。
    static func items(accounts: [Account], selectedIDs: [UUID], mode: MenuBarQuotaMode = .defaultValue) -> [MenuBarQuotaItem] {
        let names = ShortLabel.labels(for: accounts.map(\.label))
        return selectedIDs.compactMap { id in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return nil }
            let account = accounts[index]
            return MenuBarQuotaItem(
                id: account.id,
                platform: account.platform,
                name: names[index],
                percentages: percentages(for: account, mode: mode)
            )
        }
    }

    /// 帳號沒有所選的任何時窗時（例如 Copilot 只有月、選了段），退回顯示剩餘最少的那格，不讓整段只剩 --。
    static func percentages(for account: Account, mode: MenuBarQuotaMode) -> [String] {
        let windows = account.quota?.primaryWindows ?? []
        guard !windows.isEmpty else { return ["--"] }
        let matched = mode.kinds.compactMap { kind in windows.first { $0.kind == kind } }
        let shown = matched.isEmpty ? [windows.min { $0.remainingPercentage < $1.remainingPercentage }].compactMap { $0 } : matched
        return shown.map { "\($0.remainingPercentage)%" }
    }
}
