import AppKit
import ApplicationServices

/// 目前接上的螢幕。座標都已換成左上角為原點的全域座標，與 Accessibility 一致。
struct ConnectedDisplay: Hashable, Sendable {
    let uuid: String
    let name: String
    let frame: CGRect
    let visibleFrame: CGRect

    var reference: DisplayReference { DisplayReference(uuid: uuid, name: name) }
}

struct DisplaySwapResult: Sendable {
    var moved = 0
    var failed = 0
}

/// 透過 Accessibility 搬其他 App 的視窗。需要使用者在「隱私權與安全性 > 輔助使用」允許 AspaceI。
final class DisplaySwapService: Sendable {
    static let shared = DisplaySwapService()

    /// 單一 App 沒有回應時最多等這麼久，避免一個卡住的 App 拖住整次互換。
    private static let messagingTimeout: Float = 0.3
    /// Accessibility 與視窗清單的座標可能差到小數點，比對時容許的誤差。
    private static let matchTolerance: CGFloat = 2

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
                uuid: uuid,
                name: screen.localizedName,
                frame: CGDisplayBounds(displayID),
                visibleFrame: CGRect(x: visible.minX, y: primaryHeight - visible.maxY, width: visible.width, height: visible.height)
            )
        }
    }

    /// 只搬目前畫面上看得到的視窗：最小化、全螢幕、其他桌面空間裡的視窗都留在原處。
    func swap(_ first: ConnectedDisplay, _ second: ConnectedDisplay, excluding ownPID: pid_t) -> DisplaySwapResult {
        let windows = visibleWindows(excluding: ownPID)
        let moves = DisplaySwapGeometry.plan(
            windows: windows.map(\.frame),
            screens: [first.frame, second.frame],
            visible: [first.visibleFrame, second.visibleFrame],
            first: 0,
            second: 1
        )
        var result = DisplaySwapResult()
        for (index, target) in moves {
            if move(windows[index].element, to: target) {
                result.moved += 1
            } else {
                result.failed += 1
            }
        }
        return result
    }

    private func visibleWindows(excluding ownPID: pid_t) -> [(element: AXUIElement, frame: CGRect)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        var onScreen: [pid_t: [CGRect]] = [:]
        for entry in info {
            // 第 0 層才是一般視窗；選單列、Dock、浮動提示都在其他層。
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pid != ownPID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            onScreen[pid, default: []].append(bounds)
        }

        var result: [(element: AXUIElement, frame: CGRect)] = []
        for (pid, frames) in onScreen {
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
            guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
            for window in windows {
                if (attribute(window, kAXMinimizedAttribute) as? Bool) == true { continue }
                if (attribute(window, "AXFullScreen") as? Bool) == true { continue }
                guard let frame = frame(of: window),
                      frames.contains(where: { Self.matches($0, frame) }) else { continue }
                result.append((window, frame))
            }
        }
        return result
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= matchTolerance && abs(lhs.minY - rhs.minY) <= matchTolerance
            && abs(lhs.width - rhs.width) <= matchTolerance && abs(lhs.height - rhs.height) <= matchTolerance
    }

    /// 先改大小再移位置、最後再改一次大小：從大螢幕搬到小螢幕時，視窗可能因為會超出邊界而拒絕先放大或先移動。
    private func move(_ window: AXUIElement, to target: CGRect) -> Bool {
        var size = target.size
        var origin = target.origin
        guard let sizeValue = AXValueCreate(.cgSize, &size),
              let originValue = AXValueCreate(.cgPoint, &origin) else { return false }
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let positionError = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, originValue)
        AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        return positionError == .success
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        guard let positionValue = attribute(window, kAXPositionAttribute),
              let sizeValue = attribute(window, kAXSizeAttribute),
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        // CF 型別無法用 as? 檢查，上面已比對過型別編號，這裡才轉。
        guard AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
