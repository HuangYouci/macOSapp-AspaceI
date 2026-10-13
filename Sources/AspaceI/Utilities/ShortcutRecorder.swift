import AppKit

/// 錄一組快捷鍵。只在 popup 開著時有效（用 App 內的按鍵監聽）。⎋ 取消、⌫ 清除。
@MainActor
final class ShortcutRecorder {
    enum Outcome {
        case recorded(KeyShortcut)
        case cleared
        case cancelled
    }

    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51

    private var monitor: Any?
    private var completion: ((Outcome) -> Void)?

    var isRecording: Bool { monitor != nil }

    func start(_ completion: @escaping (Outcome) -> Void) {
        stop()
        GlobalHotKeys.shared.suspend()
        self.completion = completion
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent 不能跨隔離區傳遞，先取出需要的值。
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, flags: flags, characters: characters) ?? false
            }
            return consumed ? nil : event
        }
    }

    /// 中途離開畫面時呼叫，視同取消。
    func stop() {
        finish(.cancelled)
    }

    private func finish(_ outcome: Outcome) {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        let completion = self.completion
        self.completion = nil
        GlobalHotKeys.shared.resume()
        completion?(outcome)
    }

    /// 回傳 true 表示按鍵被錄製吃掉，不再往下傳給文字框或選單。
    private func handle(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        let hasModifier = !flags.intersection([.command, .option, .control]).isEmpty
        if !hasModifier && keyCode == Self.escapeKeyCode {
            finish(.cancelled)
            return true
        }
        if !hasModifier && keyCode == Self.deleteKeyCode {
            finish(.cleared)
            return true
        }
        let shortcut = KeyShortcut(
            keyCode: UInt32(keyCode),
            modifiers: Self.carbonModifiers(flags),
            keyLabel: KeyShortcut.label(keyCode: UInt32(keyCode), characters: characters)
        )
        // 沒有 ⌘⌥⌃ 的組合會吃掉一般打字，繼續等下一個按鍵。
        guard shortcut.isUsable else { return true }
        finish(.recorded(shortcut))
        return true
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= KeyShortcut.command }
        if flags.contains(.shift) { value |= KeyShortcut.shift }
        if flags.contains(.option) { value |= KeyShortcut.option }
        if flags.contains(.control) { value |= KeyShortcut.control }
        return value
    }
}
