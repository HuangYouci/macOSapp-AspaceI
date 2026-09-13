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

    @Test("最多三個，已刪除的帳號略過")
    func limitsToThreeAndSkipsMissing() {
        let accounts = (0..<4).map { _ in account(.codex, email: nil, windows: []) }
        let ids = [UUID()] + accounts.map(\.id)
        let items = MenuBarQuotaItem.items(accounts: accounts, selectedIDs: ids)
        #expect(items.count == 2)
    }
}
