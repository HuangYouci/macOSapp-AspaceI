import AppKit
import Observation
import os

/// 螢幕全黑：所有螢幕蓋上黑色視窗、能調的螢幕把亮度降到最低，動滑鼠或按任意鍵就還原。
@MainActor
@Observable
final class BlackoutManager {
    private static let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "Blackout")
    /// 按下開始的那一下、手離開觸控板時的微小位移都會送出事件，剛蓋上的這段時間不算。
    private static let graceInterval: TimeInterval = 0.6
    private static let exitEvents: NSEvent.EventTypeMask = [
        .mouseMoved, .leftMouseDown, .rightMouseDown, .otherMouseDown,
        .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        .scrollWheel, .keyDown, .flagsChanged, .systemDefined
    ]

    private(set) var isActive = false

    @ObservationIgnored private let overlay = BlackoutOverlay()
    @ObservationIgnored private let brightnessService = DisplayBrightnessService.shared
    /// 調暗前的亮度，結束時逐一還原。
    @ObservationIgnored private var savedBrightness: [CGDirectDisplayID: Float] = [:]
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var startedAt: TimeInterval = 0
    @ObservationIgnored private var previousApp: NSRunningApplication?

    func start() {
        guard !isActive else { return }
        isActive = true
        startedAt = ProcessInfo.processInfo.systemUptime
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost

        NSApplication.shared.activate()
        overlay.show()
        dimDisplays()
        NSCursor.hide()
        installMonitors()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                // 中途接上的螢幕也要蓋到、調暗；已調暗的不重複記錄，否則會把 0 當成原本的亮度。
                self.overlay.show()
                self.dimDisplays()
            }
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
        screenObserver = nil
        for (displayID, value) in savedBrightness {
            brightnessService.setBrightness(value, of: displayID)
        }
        savedBrightness = [:]
        overlay.dismiss()
        NSCursor.unhide()
        previousApp?.activate()
        previousApp = nil
    }

    private func dimDisplays() {
        for displayID in Self.activeDisplayIDs() where savedBrightness[displayID] == nil {
            guard let value = brightnessService.brightness(of: displayID) else { continue }
            if brightnessService.setBrightness(0, of: displayID) {
                savedBrightness[displayID] = value
            }
        }
    }

    /// AspaceI 在前景時事件由 local monitor 收、並吞掉，不會漏到底下的 App；
    /// 被其他 App 搶走前景時改由 global monitor 收（鍵盤事件要有輔助使用權限才收得到，滑鼠不需要）。
    private func installMonitors() {
        if let local = NSEvent.addLocalMonitorForEvents(matching: Self.exitEvents, handler: { [weak self] event in
            // NSEvent 不是 Sendable，不能當 assumeIsolated 的回傳值帶出來，只帶判斷結果。
            let timestamp = event.timestamp
            let consumed = MainActor.assumeIsolated {
                guard let self, self.isActive else { return false }
                return self.handle(timestamp: timestamp)
            }
            return consumed ? nil : event
        }) {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: Self.exitEvents, handler: { [weak self] event in
            let timestamp = event.timestamp
            MainActor.assumeIsolated {
                guard let self, self.isActive else { return }
                _ = self.handle(timestamp: timestamp)
            }
        }) {
            monitors.append(global)
        }
    }

    /// 回傳 true 表示事件已處理、不再往下傳。
    private func handle(timestamp: TimeInterval) -> Bool {
        guard timestamp - startedAt >= Self.graceInterval else { return true }
        Self.logger.info("偵測到輸入，結束螢幕全黑")
        stop()
        return true
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }
}
