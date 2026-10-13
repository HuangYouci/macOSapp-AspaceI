import AppKit
import Observation

/// 螢幕互換：保存要互換的螢幕組合、註冊各組的快捷鍵、執行互換。
@MainActor
@Observable
final class DisplaySwapManager {
    private static let rulesKey = "displaySwapRules"
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51

    private(set) var rules: [DisplaySwapRule] = []
    private(set) var displays: [ConnectedDisplay] = []
    private(set) var isTrusted = false
    private(set) var recordingRuleID: UUID?
    /// 快捷鍵已被其他 App 註冊走、這裡註冊不到的組合。
    private(set) var conflictedRuleIDs: Set<UUID> = []
    private(set) var isSwapping = false
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service = DisplaySwapService.shared
    @ObservationIgnored private let hotKeys = GlobalHotKeys()
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.rulesKey) {
            do {
                rules = try JSONDecoder().decode([DisplaySwapRule].self, from: data)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func start() {
        guard screenObserver == nil else { return }
        refreshDisplays()
        refreshTrust()
        registerHotKeys()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshDisplays() }
        }
    }

    func refreshDisplays() {
        displays = service.connectedDisplays()
    }

    /// 授權結果沒有通知可以聽，畫面開著時定期呼叫。
    func refreshTrust() {
        isTrusted = service.isTrusted(prompt: false)
    }

    /// 跳出系統的授權提示，並打開「輔助使用」設定。
    func requestTrust() {
        isTrusted = service.isTrusted(prompt: true)
    }

    func display(for reference: DisplayReference) -> ConnectedDisplay? {
        displays.first { $0.uuid == reference.uuid }
    }

    /// 接著已有組合挑還沒用過的兩個螢幕；只接一個螢幕時不新增。
    func addRule() {
        guard displays.count >= 2 else { return }
        let used = Set(rules.flatMap { [$0.first.uuid, $0.second.uuid] })
        let ordered = displays.filter { !used.contains($0.uuid) } + displays.filter { used.contains($0.uuid) }
        rules.append(DisplaySwapRule(first: ordered[0].reference, second: ordered[1].reference))
        save()
    }

    func addRuleIfEmpty() {
        if rules.isEmpty { addRule() }
    }

    func setDisplays(_ ruleID: UUID, first: DisplayReference? = nil, second: DisplayReference? = nil) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        if let first { rules[index].first = first }
        if let second { rules[index].second = second }
        save()
    }

    func remove(_ ruleID: UUID) {
        if recordingRuleID == ruleID { stopRecording() }
        rules.removeAll { $0.id == ruleID }
        save()
        registerHotKeys()
    }

    // MARK: 錄製快捷鍵

    /// 錄製期間先拿掉所有熱鍵，否則按下已註冊的組合會直接觸發互換，錄不進來。
    func startRecording(_ ruleID: UUID) {
        stopRecording()
        hotKeys.removeAll()
        recordingRuleID = ruleID
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // NSEvent 不能跨隔離區傳遞，先取出需要的值。
            let keyCode = event.keyCode
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let characters = event.charactersIgnoringModifiers
            let consumed = MainActor.assumeIsolated {
                self?.handleRecording(keyCode: keyCode, flags: flags, characters: characters) ?? false
            }
            return consumed ? nil : event
        }
    }

    func stopRecording() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        guard recordingRuleID != nil else { return }
        recordingRuleID = nil
        registerHotKeys()
    }

    func clearShortcut(_ ruleID: UUID) {
        setShortcut(nil, for: ruleID)
    }

    /// 回傳 true 表示按鍵被錄製吃掉，不再往下傳給文字框或選單。
    private func handleRecording(keyCode: UInt16, flags: NSEvent.ModifierFlags, characters: String?) -> Bool {
        guard let ruleID = recordingRuleID else { return false }
        let hasModifier = !flags.intersection([.command, .option, .control]).isEmpty
        if !hasModifier && keyCode == Self.escapeKeyCode {
            stopRecording()
            return true
        }
        if !hasModifier && keyCode == Self.deleteKeyCode {
            setShortcut(nil, for: ruleID)
            stopRecording()
            return true
        }
        let shortcut = KeyShortcut(
            keyCode: UInt32(keyCode),
            modifiers: Self.carbonModifiers(flags),
            keyLabel: KeyShortcut.label(keyCode: UInt32(keyCode), characters: characters)
        )
        // 沒有 ⌘⌥⌃ 的組合會吃掉一般打字，繼續等下一個按鍵。
        guard shortcut.isUsable else { return true }
        setShortcut(shortcut, for: ruleID)
        stopRecording()
        return true
    }

    private func setShortcut(_ shortcut: KeyShortcut?, for ruleID: UUID) {
        guard let index = rules.firstIndex(where: { $0.id == ruleID }) else { return }
        // 同一組快捷鍵只留給最後設定的那一組，舊的清掉，避免兩組搶同一個按鍵。
        if let shortcut {
            for other in rules.indices where other != index && rules[other].shortcut == shortcut {
                rules[other].shortcut = nil
            }
        }
        rules[index].shortcut = shortcut
        save()
        registerHotKeys()
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= KeyShortcut.command }
        if flags.contains(.shift) { value |= KeyShortcut.shift }
        if flags.contains(.option) { value |= KeyShortcut.option }
        if flags.contains(.control) { value |= KeyShortcut.control }
        return value
    }

    // MARK: 互換

    func swap(_ ruleID: UUID) async {
        guard !isSwapping, let rule = rules.first(where: { $0.id == ruleID }) else { return }
        refreshDisplays()
        guard let first = display(for: rule.first), let second = display(for: rule.second) else {
            let missing = display(for: rule.first) == nil ? rule.first.name : rule.second.name
            fail("「\(missing)」沒有接上")
            return
        }
        guard first.uuid != second.uuid else {
            fail("兩邊選了同一個螢幕")
            return
        }
        refreshTrust()
        guard isTrusted else {
            requestTrust()
            fail("需要輔助使用權限")
            return
        }
        isSwapping = true
        defer { isSwapping = false }
        let service = self.service
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let result = await Task.detached {
            service.swap(first, second, excluding: ownPID)
        }.value
        errorMessage = result.failed > 0 ? "\(result.failed) 個視窗搬不動" : nil
    }

    /// 快捷鍵觸發時 popup 通常沒開，看不到訊息，所以同時發出提示音。
    private func fail(_ message: String) {
        errorMessage = message
        NSSound.beep()
    }

    private func registerHotKeys() {
        let items = rules.compactMap { rule -> (id: UUID, shortcut: KeyShortcut, action: () -> Void)? in
            guard let shortcut = rule.shortcut else { return nil }
            let id = rule.id
            return (id, shortcut, { [weak self] in
                Task { await self?.swap(id) }
            })
        }
        conflictedRuleIDs = hotKeys.replaceAll(items)
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(rules), forKey: Self.rulesKey)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
