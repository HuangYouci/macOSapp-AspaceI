import ApplicationServices
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
    @Test("額度只列段、週、月，帶著重置時間；沒有額度是空的")
    func quota() {
        let reset = Date(timeIntervalSince1970: 1_700_000_000)
        let account = Account(
            platform: .claude,
            displayName: "Claude",
            quota: QuotaSnapshot(windows: [
                QuotaWindow(id: "7d", title: "7d", remainingPercentage: 40, resetsAt: nil, kind: .week),
                QuotaWindow(id: "5h", title: "5h", remainingPercentage: 62, resetsAt: reset, kind: .fiveHour)
            ], fetchedAt: .now)
        )
        // 標籤跟著系統語系（zh-Hant 是段／週，en 是 S／W）。
        #expect(TaskModeManager.quota(account) == [
            TaskSidebarView.Quota(title: QuotaWindow.Kind.fiveHour.shortTitle, remainingPercentage: 62, resetsAt: reset),
            TaskSidebarView.Quota(title: QuotaWindow.Kind.week.shortTitle, remainingPercentage: 40, resetsAt: nil)
        ])
        #expect(TaskModeManager.quota(nil).isEmpty)
    }

    @Test("App 忙到 Accessibility 逾時時沿用上一輪的視窗；視窗伺服器不再列出的才拿掉")
    func carriesOverUnresponsiveWindows() {
        let element = AXUIElementCreateApplication(1)
        let busy = TaskWindow(id: 7, pid: 1, title: "busy", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let gone = TaskWindow(id: 8, pid: 1, title: "gone", frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        let fresh = TaskWindow(id: 9, pid: 2, title: "fresh", frame: CGRect(x: 10, y: 10, width: 800, height: 600))
        var scan = TaskWindowScan()
        scan.windows = [fresh]
        scan.elements = [9: element]
        let moved = CGRect(x: 5, y: 5, width: 900, height: 700)
        scan.listed = [7: (order: 0, frame: moved), 9: (order: 1, frame: fresh.frame)]

        let merged = scan.carryingOver([busy, gone], elements: [7: element, 8: element])
        // 疊放順序照視窗伺服器，外框用它最新的。
        #expect(merged.windows.map(\.id) == [7, 9])
        #expect(merged.windows.first?.frame == moved)
        #expect(merged.elements[7] != nil)
        #expect(merged.elements[8] == nil)
    }

    @MainActor
    @Test("點側欄後疊放順序還沒跟上時維持點的那個，跟上、逾時或被關掉才交還")
    func selectionHold() {
        let now = ContinuousClock.now
        let pending = (id: CGWindowID(2), until: now + .seconds(1))
        let current: Set<CGWindowID> = [1, 2, 3]

        let lagging = TaskModeManager.resolveSelection(front: 1, pending: pending, now: now, current: current)
        #expect(lagging.selection == 2)
        #expect(lagging.keepsPending)

        let caughtUp = TaskModeManager.resolveSelection(front: 2, pending: pending, now: now, current: current)
        #expect(caughtUp.selection == 2)
        #expect(!caughtUp.keepsPending)

        let expired = TaskModeManager.resolveSelection(front: 1, pending: pending, now: now + .seconds(2), current: current)
        #expect(expired.selection == 1)

        let closed = TaskModeManager.resolveSelection(front: 1, pending: pending, now: now, current: [1, 3])
        #expect(closed.selection == 1)

        let none = TaskModeManager.resolveSelection(front: 3, pending: nil, now: now, current: current)
        #expect(none.selection == 3)
    }

    @Test("互換時還在工作區的視窗直接落在新螢幕的工作區，使用者挪過的不算")
    func workspaceTargetsFollowSwap() {
        let inWorkspace = TaskModeLayout.mainFrame(in: laptop).offsetBy(dx: 1, dy: 0)
        let moved = CGRect(x: 100, y: 100, width: 600, height: 400)
        let targets = TaskModeLayout.workspaceTargets([1: inWorkspace, 2: moved], from: laptop, to: wide)
        #expect(targets == [1: TaskModeLayout.mainFrame(in: wide)])
    }

    @Test("互換後要還原的位置也換到另一個螢幕，兩邊都不在的不動")
    func originalFramesFollowSwap() {
        let laptopScreen = CGRect(x: 0, y: 0, width: 1452, height: 982)
        let wideScreen = CGRect(x: -515, y: -1440, width: 2560, height: 1440)
        let elsewhere = CGRect(x: 5000, y: 0, width: 300, height: 300)
        let original: [CGWindowID: CGRect] = [1: laptop, 2: elsewhere]
        let swapped = TaskModeLayout.swappedFrames(original, screens: [laptopScreen, wideScreen], visible: [laptop, wide])
        #expect(swapped[1] == wide)
        #expect(swapped[2] == elsewhere)
    }
}
