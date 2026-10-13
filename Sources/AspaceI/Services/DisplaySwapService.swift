import AppKit
import ApplicationServices

/// 目前接上的螢幕。座標都已換成左上角為原點的全域座標，與 Accessibility 一致。
struct ConnectedDisplay: Hashable, Sendable {
    let displayID: CGDirectDisplayID
    let uuid: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect
    let scale: CGFloat

    var reference: DisplayReference { DisplayReference(uuid: uuid, name: name) }
}

struct DisplaySwapResult: Sendable {
    var moved = 0
    var failed = 0
}

/// 要搬的一個視窗。`windowNumber` 對應視窗清單與 ScreenCaptureKit 的編號，`order` 越小越在前面。
struct PlannedWindowMove: Sendable {
    let windowNumber: CGWindowID
    let order: Int
    let from: CGRect
    let to: CGRect
}

/// 讀完、算好但還沒搬的結果。裡面握著 Accessibility 物件，只在 `DisplaySwapService` 內使用，
/// 外面只看 `moves`；建立後不再修改，跨執行緒傳遞是安全的。
final class DisplaySwapPlan: @unchecked Sendable {
    fileprivate struct AppMoves {
        let app: AXUIElement
        let windows: [(element: AXUIElement, move: PlannedWindowMove)]
    }

    fileprivate let apps: [AppMoves]
    let moves: [PlannedWindowMove]

    fileprivate init(apps: [AppMoves]) {
        self.apps = apps
        moves = apps.flatMap { $0.windows.map(\.move) }
    }
}

/// 透過 Accessibility 搬其他 App 的視窗。需要使用者在「隱私權與安全性 > 輔助使用」允許 AspaceI。
final class DisplaySwapService: Sendable {
    static let shared = DisplaySwapService()

    /// 單一 App 沒有回應時最多等這麼久，避免一個卡住的 App 拖住整次互換。
    private static let messagingTimeout: Float = 0.3
    /// Accessibility 與視窗清單的座標可能差到小數點，比對時容許的誤差。
    private static let matchTolerance: CGFloat = 2
    private static let enhancedUserInterface = "AXEnhancedUserInterface"

    func isTrusted(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    func connectedDisplays() -> [ConnectedDisplay] {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let displayID = CGDirectDisplayID(number.uint32Value)
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
                  let uuid = CFUUIDCreateString(nil, cfUUID) as String? else { return nil }
            let visible = screen.visibleFrame
            return ConnectedDisplay(
                displayID: displayID,
                uuid: uuid,
                name: screen.localizedName,
                frame: CGDisplayBounds(displayID),
                visibleFrame: CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height),
                scale: screen.backingScaleFactor
            )
        }
    }

    /// 只算不搬。只看目前畫面上看得到的視窗：最小化、全螢幕、其他桌面空間裡的視窗都留在原處。
    /// 每個 App 各自在一條執行緒上讀，總耗時取決於最慢的那個 App，而不是全部加總。
    /// `overrides` 指定的視窗（任務管理工作區裡的）不照比例換算，直接搬到指定位置；只在它本來就要被搬時才生效。
    func plan(_ first: ConnectedDisplay, _ second: ConnectedDisplay, excluding ownPID: pid_t, overrides: [CGWindowID: CGRect] = [:]) -> DisplaySwapPlan {
        let apps = onScreenWindows(excluding: ownPID)
        let screens = [first.frame, second.frame]
        let visible = [first.visibleFrame, second.visibleFrame]
        let collector = LockedCollector<DisplaySwapPlan.AppMoves>()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            if let moves = planWindows(of: apps[index].pid, onScreen: apps[index].windows, screens: screens, visible: visible, overrides: overrides) {
                collector.append(moves)
            }
        }
        return DisplaySwapPlan(apps: collector.items)
    }

    /// 各 App 同時搬。
    func execute(_ plan: DisplaySwapPlan) -> DisplaySwapResult {
        let collector = LockedCollector<DisplaySwapResult>()
        DispatchQueue.concurrentPerform(iterations: plan.apps.count) { index in
            collector.append(execute(plan.apps[index]))
        }
        return collector.items.reduce(into: DisplaySwapResult()) {
            $0.moved += $1.moved
            $0.failed += $1.failed
        }
    }

    private struct OnScreenWindow {
        let number: CGWindowID
        let order: Int
        let frame: CGRect
    }

    private func onScreenWindows(excluding ownPID: pid_t) -> [(pid: pid_t, windows: [OnScreenWindow])] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var onScreen: [pid_t: [OnScreenWindow]] = [:]
        // 清單由前到後排列，順序就是疊放順序。
        for (order, entry) in info.enumerated() {
            // 第 0 層才是一般視窗；選單列、Dock、浮動提示都在其他層。
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            onScreen[pid, default: []].append(OnScreenWindow(number: number, order: order, frame: bounds))
        }
        return onScreen.map { ($0.key, $0.value) }
    }

    private func planWindows(
        of pid: pid_t,
        onScreen: [OnScreenWindow],
        screens: [CGRect],
        visible: [CGRect],
        overrides: [CGWindowID: CGRect]
    ) -> DisplaySwapPlan.AppMoves? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
        guard let elements = AXWindow.attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return nil }
        var windows: [(element: AXUIElement, listed: OnScreenWindow)] = []
        for window in elements {
            if (AXWindow.attribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
            if (AXWindow.attribute(window, "AXFullScreen") as? Bool) == true { continue }
            guard let frame = AXWindow.frame(of: window),
                  let listed = onScreen.first(where: { Self.matches($0.frame, frame) }) else { continue }
            windows.append((window, OnScreenWindow(number: listed.number, order: listed.order, frame: frame)))
        }
        let targets = DisplaySwapGeometry.plan(windows: windows.map(\.listed.frame), screens: screens, visible: visible, first: 0, second: 1)
        guard !targets.isEmpty else { return nil }
        let moves = targets.map { index, target in
            let listed = windows[index].listed
            let destination = overrides[listed.number] ?? target
            return (windows[index].element, PlannedWindowMove(windowNumber: listed.number, order: listed.order, from: listed.frame, to: destination))
        }
        return DisplaySwapPlan.AppMoves(app: app, windows: moves)
    }

    private func execute(_ moves: DisplaySwapPlan.AppMoves) -> DisplaySwapResult {
        // 輔助增強模式開著時（Finder、開過螢幕閱讀器的瀏覽器），App 會用動畫慢慢移過去，搬完再開回來。
        let enhanced = (AXWindow.attribute(moves.app, Self.enhancedUserInterface) as? Bool) == true
        if enhanced {
            AXUIElementSetAttributeValue(moves.app, Self.enhancedUserInterface as CFString, kCFBooleanFalse)
        }
        defer {
            if enhanced {
                AXUIElementSetAttributeValue(moves.app, Self.enhancedUserInterface as CFString, kCFBooleanTrue)
            }
        }
        var result = DisplaySwapResult()
        for window in moves.windows {
            if AXWindow.move(window.element, from: window.move.from, to: window.move.to) {
                result.moved += 1
            } else {
                result.failed += 1
            }
        }
        return result
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= matchTolerance && abs(lhs.minY - rhs.minY) <= matchTolerance
            && abs(lhs.width - rhs.width) <= matchTolerance && abs(lhs.height - rhs.height) <= matchTolerance
    }
}
