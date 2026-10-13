import CoreGraphics
import Foundation
import Testing
@testable import AspaceI

struct TaskModeTests {
    private let wide = CGRect(x: -515, y: -1440, width: 2560, height: 1440)
    private let laptop = CGRect(x: 0, y: 33, width: 1452, height: 949)

    @Test("大螢幕的側欄停在寬度上限，工作區接在右邊到底")
    func wideLayout() {
        let sidebar = TaskModeLayout.sidebarFrame(in: wide)
        let main = TaskModeLayout.mainFrame(in: wide)
        #expect(sidebar.width == TaskModeLayout.maxSidebarWidth)
        #expect(sidebar.minX == wide.minX + TaskModeLayout.margin)
        #expect(main.minX == sidebar.maxX + TaskModeLayout.margin)
        #expect(main.maxX == wide.maxX - TaskModeLayout.margin)
        #expect(main.minY == sidebar.minY)
        #expect(main.height == sidebar.height)
    }

    @Test("小螢幕的側欄依比例縮小，不會吃掉工作區")
    func narrowLayout() {
        let narrow = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(TaskModeLayout.sidebarWidth(in: narrow) == 160)
        #expect(TaskModeLayout.mainFrame(in: narrow).width == 800 - 160 - TaskModeLayout.margin * 3)
    }

    @Test("側欄與工作區都在螢幕可用範圍內、互不重疊")
    func staysInside() {
        for visible in [wide, laptop] {
            let sidebar = TaskModeLayout.sidebarFrame(in: visible)
            let main = TaskModeLayout.mainFrame(in: visible)
            #expect(visible.contains(sidebar))
            #expect(visible.contains(main))
            #expect(!sidebar.intersects(main))
        }
    }

    @MainActor
    @Test("額度只列段、週、月，沒有額度顯示 --")
    func quotaText() {
        let account = Account(
            platform: .claude,
            displayName: "Claude",
            quota: QuotaSnapshot(windows: [
                QuotaWindow(id: "7d", title: "7d", remainingPercentage: 40, resetsAt: nil, kind: .week),
                QuotaWindow(id: "5h", title: "5h", remainingPercentage: 62, resetsAt: nil, kind: .fiveHour)
            ], fetchedAt: .now)
        )
        // 標籤跟著系統語系（zh-Hant 是段／週，en 是 S／W）。
        let expected = "\(QuotaWindow.Kind.fiveHour.shortTitle) 62% · \(QuotaWindow.Kind.week.shortTitle) 40%"
        #expect(TaskModeManager.quotaText(account) == expected)
        #expect(TaskModeManager.quotaText(nil) == "--")
    }
}
