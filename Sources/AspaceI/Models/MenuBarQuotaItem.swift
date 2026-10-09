import Foundation

struct MenuBarQuotaItem: Equatable, Identifiable, Sendable {
    static let limit = 3

    let id: UUID
    let platform: PlatformKind
    let name: String
    let percentages: [String]

    /// 依使用者選取順序組出 menu bar 項目；已刪除的帳號直接略過。
    /// 短名稱在所有帳號之間比（不只選到的），同一個帳號在 menu bar 與實例圖示上永遠是同一個。
    static func items(accounts: [Account], selectedIDs: [UUID]) -> [MenuBarQuotaItem] {
        let names = ShortLabel.labels(for: accounts.map(\.label))
        return selectedIDs.prefix(limit).compactMap { id in
            guard let index = accounts.firstIndex(where: { $0.id == id }) else { return nil }
            let account = accounts[index]
            return MenuBarQuotaItem(
                id: account.id,
                platform: account.platform,
                name: names[index],
                percentages: percentages(for: account)
            )
        }
    }

    private static func percentages(for account: Account) -> [String] {
        let windows = account.quota?.primaryWindows ?? []
        guard !windows.isEmpty else { return ["--"] }
        let expected: [QuotaWindow.Kind] = windows.contains { $0.kind == .month } ? [.month] : [.fiveHour, .week]
        return expected.compactMap { kind in
            guard let window = windows.first(where: { $0.kind == kind }) else {
                return kind == .fiveHour ? nil : "--"
            }
            return "\(window.remainingPercentage)%"
        }
    }
}
