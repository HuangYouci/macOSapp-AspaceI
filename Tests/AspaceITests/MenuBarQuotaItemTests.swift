import Foundation
import Testing
@testable import AspaceI

struct MenuBarQuotaItemTests {
    private func account(_ platform: PlatformKind, email: String?, windows: [QuotaWindow]) -> Account {
        Account(
            platform: platform,
            displayName: platform.displayName,
            email: email,
            quota: windows.isEmpty ? nil : QuotaSnapshot(windows: windows, fetchedAt: .now)
        )
    }

    @Test("依選取順序輸出帳號前三字與 5h、7d 百分比")
    func formatsSelectedAccountsInOrder() {
        let claude = account(.claude, email: "huangyouci@gmail.com", windows: [
            QuotaWindow(id: "5h", title: "5h", remainingPercentage: 82, resetsAt: nil, kind: .fiveHour),
            QuotaWindow(id: "7d", title: "7d", remainingPercentage: 64, resetsAt: nil, kind: .week)
        ])
        let copilot = account(.githubCopilot, email: "octocat", windows: [
            QuotaWindow(id: "premium", title: "月", remainingPercentage: 40, resetsAt: nil, kind: .month)
        ])
        let items = MenuBarQuotaItem.items(accounts: [claude, copilot], selectedIDs: [copilot.id, claude.id])
        #expect(items.map(\.name) == ["oct", "hua"])
        #expect(items.map(\.percentages) == [["40%"], ["82%", "64%"]])
    }

    @Test("只有週額度時省略 5h，沒有額度時顯示 --")
    func handlesMissingWindows() {
        let codex = account(.codex, email: nil, windows: [
            QuotaWindow(id: "week", title: "7d", remainingPercentage: 27, resetsAt: nil, kind: .week)
        ])
        let empty = account(.antigravity, email: nil, windows: [])
        let items = MenuBarQuotaItem.items(accounts: [codex, empty], selectedIDs: [codex.id, empty.id])
        #expect(items.map(\.percentages) == [["27%"], ["--"]])
        #expect(items.first?.name == "Cod")
    }

    @Test("短名稱在所有帳號之間比：選單只選一個也要跟沒選到的撞名帳號區分")
    func disambiguatesAgainstAllAccounts() {
        let work = account(.claude, email: "huangwork@x.com", windows: [])
        let home = account(.codex, email: "huanghome@y.com", windows: [])
        let items = MenuBarQuotaItem.items(accounts: [work, home], selectedIDs: [home.id])
        #expect(items.map(\.name) == ["huh"])
    }

    @Test("數量不設上限，已刪除的帳號略過")
    func showsAllSelectedAndSkipsMissing() {
        let accounts = (0..<5).map { _ in account(.codex, email: nil, windows: []) }
        let ids = [UUID()] + accounts.map(\.id)
        let items = MenuBarQuotaItem.items(accounts: accounts, selectedIDs: ids)
        #expect(items.count == 5)
    }

    private var fullAccount: Account {
        account(.claude, email: "a@x.com", windows: [
            QuotaWindow(id: "5h", title: "5h", remainingPercentage: 82, resetsAt: nil, kind: .fiveHour),
            QuotaWindow(id: "7d", title: "7d", remainingPercentage: 21, resetsAt: nil, kind: .week),
            QuotaWindow(id: "1m", title: "1m", remainingPercentage: 55, resetsAt: nil, kind: .month)
        ])
    }

    @Test("各額度類型只取對應時窗", arguments: [
        (MenuBarQuotaMode.session, ["82%"]),
        (.week, ["21%"]),
        (.month, ["55%"]),
        (.sessionAndWeek, ["82%", "21%"]),
        (.lowest, ["21%"])
    ])
    func modeSelectsWindows(mode: MenuBarQuotaMode, expected: [String]) {
        #expect(MenuBarQuotaItem.percentages(for: fullAccount, mode: mode) == expected)
    }

    @Test("帳號沒有所選時窗時退回剩餘最少的那格")
    func fallsBackToLowestWhenKindMissing() {
        let copilot = account(.githubCopilot, email: "octocat", windows: [
            QuotaWindow(id: "premium", title: "月", remainingPercentage: 40, resetsAt: nil, kind: .month)
        ])
        let codex = account(.codex, email: nil, windows: [
            QuotaWindow(id: "5h", title: "5h", remainingPercentage: 90, resetsAt: nil, kind: .fiveHour),
            QuotaWindow(id: "7d", title: "7d", remainingPercentage: 30, resetsAt: nil, kind: .week)
        ])
        #expect(MenuBarQuotaItem.percentages(for: copilot, mode: .session) == ["40%"])
        #expect(MenuBarQuotaItem.percentages(for: codex, mode: .month) == ["30%"])
    }

    @Test("沒有額度時任何類型都顯示 --", arguments: MenuBarQuotaMode.allCases)
    func emptyQuotaShowsPlaceholder(mode: MenuBarQuotaMode) {
        let empty = account(.antigravity, email: nil, windows: [])
        #expect(MenuBarQuotaItem.percentages(for: empty, mode: mode) == ["--"])
    }
}
