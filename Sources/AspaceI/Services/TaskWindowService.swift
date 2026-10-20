import AppKit
@preconcurrency import ApplicationServices

/// 任務管理接手的一個視窗。`id` 是視窗清單與 ScreenCaptureKit 共用的編號。
struct TaskWindow: Identifiable, Hashable, Sendable {
    let id: CGWindowID
    let pid: pid_t
    var title: String
    var frame: CGRect
}

/// 一輪掃描的結果。Accessibility 物件建立後不再修改，跨執行緒傳遞是安全的。
struct TaskWindowScan: @unchecked Sendable {
    /// 由前到後排列，第一個就是目前最上層的視窗。
    var windows: [TaskWindow] = []
    var elements: [CGWindowID: AXUIElement] = [:]
    /// 視窗伺服器列出的、屬於這些程序的一般視窗（疊放順序與外框）。App 忙的時候 Accessibility 會逾時，
    /// 這份清單不經過 App，仍然是準的。
    var listed: [CGWindowID: (order: Int, frame: CGRect)] = [:]

    /// 上一輪有、這一輪 Accessibility 沒讀到，但視窗伺服器還列著的視窗沿用上一輪的（外框用視窗伺服器的）。
    /// App 在忙（例如正在大量輸出）時 Accessibility 會逾時；直接當成視窗不見了，它會從側欄掉出去、
    /// 縮圖串流被關掉，下一輪讀到時又被當成新視窗搬回工作區，還會把「結束時要還原的位置」記成工作區。
    /// 最小化、全螢幕、換到別的桌面空間的視窗視窗伺服器不會列，照樣會被拿掉。
    func carryingOver(_ previous: [TaskWindow], elements previousElements: [CGWindowID: AXUIElement]) -> TaskWindowScan {
        var merged = self
        var orders = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, listed[$0.id]?.order ?? Int.max) })
        for window in previous where merged.elements[window.id] == nil {
            guard let entry = listed[window.id], let element = previousElements[window.id] else { continue }
            var kept = window
            kept.frame = entry.frame
            merged.windows.append(kept)
            merged.elements[window.id] = element
            orders[window.id] = entry.order
        }
        merged.windows.sort { (orders[$0.id] ?? Int.max) < (orders[$1.id] ?? Int.max) }
        return merged
    }
}

/// 讀與搬 AI 工具的視窗。需要輔助使用權限。
final class TaskWindowService: Sendable {
    static let shared = TaskWindowService()

    private static let messagingTimeout: Float = 0.3
    /// 搬動與拉到最前面是使用者要的動作，在背景做，可以多等忙碌的 App 一會兒。
    private static let actionTimeout: Float = 1.5
    private static let matchTolerance: CGFloat = 2
    /// 比這小的多半是浮動面板或彈出視窗，不接手。
    private static let minimumSize = CGSize(width: 300, height: 200)

    /// 只看目前桌面空間看得到、沒最小化、不是全螢幕的一般視窗；各 App 同時讀。
    func scan(pids: Set<pid_t>) -> TaskWindowScan {
        guard !pids.isEmpty,
              let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return TaskWindowScan()
        }
        var listed: [pid_t: [(number: CGWindowID, order: Int, frame: CGRect)]] = [:]
        for (order, entry) in info.enumerated() {
            guard (entry[kCGWindowLayer as String] as? Int) == 0,
                  let pid = entry[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid),
                  let number = entry[kCGWindowNumber as String] as? CGWindowID,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            listed[pid, default: []].append((number, order, bounds))
        }

        var scan = TaskWindowScan()
        for entries in listed.values {
            for entry in entries {
                scan.listed[entry.number] = (entry.order, entry.frame)
            }
        }

        let apps = Array(listed)
        let found = LockedCollector<(order: Int, window: TaskWindow, element: AXUIElement)>()
        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let (pid, entries) = apps[index]
            let app = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(app, Self.messagingTimeout)
            guard let elements = AXWindow.attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { return }
            var local: [(order: Int, window: TaskWindow, element: AXUIElement)] = []
            for element in elements {
                // 不依賴視窗物件沿用 App 的逾時，各自設；沒設時是系統預設的好幾秒，一個忙碌的 App 就拖住整輪掃描。
                AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
                guard (AXWindow.attribute(element, kAXSubroleAttribute) as? String) == kAXStandardWindowSubrole,
                      (AXWindow.attribute(element, kAXMinimizedAttribute) as? Bool) != true,
                      (AXWindow.attribute(element, "AXFullScreen") as? Bool) != true,
                      let frame = AXWindow.frame(of: element),
                      frame.width >= Self.minimumSize.width, frame.height >= Self.minimumSize.height,
                      let entry = entries.first(where: { Self.matches($0.frame, frame) }) else { continue }
                local.append((entry.order, TaskWindow(id: entry.number, pid: pid, title: AXWindow.title(of: element), frame: frame), element))
            }
            found.append(contentsOf: local)
        }

        for item in found.items.sorted(by: { $0.order < $1.order }) where scan.elements[item.window.id] == nil {
            scan.windows.append(item.window)
            scan.elements[item.window.id] = item.element
        }
        return scan
    }

    /// 各視窗同時搬，回傳搬不動的視窗。
    func place(_ moves: [(element: AXUIElement, from: CGRect, to: CGRect, id: CGWindowID)]) -> Set<CGWindowID> {
        let box = MoveBox(moves: moves)
        let failed = LockedCollector<CGWindowID>()
        DispatchQueue.concurrentPerform(iterations: box.moves.count) { index in
            let move = box.moves[index]
            AXUIElementSetMessagingTimeout(move.element, Self.actionTimeout)
            if !AXWindow.move(move.element, from: move.from, to: move.to) {
                failed.append(move.id)
            }
        }
        return Set(failed.items)
    }

    func raise(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, Self.actionTimeout)
        AXWindow.raise(element)
    }

    private static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= matchTolerance && abs(lhs.minY - rhs.minY) <= matchTolerance
            && abs(lhs.width - rhs.width) <= matchTolerance && abs(lhs.height - rhs.height) <= matchTolerance
    }
}

/// Accessibility 物件沒有標 Sendable，包一層交給並行搬動。
private struct MoveBox: @unchecked Sendable {
    let moves: [(element: AXUIElement, from: CGRect, to: CGRect, id: CGWindowID)]
}
