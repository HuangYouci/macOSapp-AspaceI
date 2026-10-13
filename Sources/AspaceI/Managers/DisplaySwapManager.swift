import AppKit
import Observation
import os

/// 螢幕互換：保存要互換的螢幕組合、註冊各組的快捷鍵、執行互換。
@MainActor
@Observable
final class DisplaySwapManager {
    private static let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "DisplaySwap")
    private static let rulesKey = "displaySwapRules"
    private static let animatesKey = "displaySwapAnimates"
    /// 視窗搬完後 App 要一點時間在新位置畫好，太早淡出會看到還沒重畫的視窗。
    private static let redrawDelay: Duration = .milliseconds(90)
    private static let escapeKeyCode: UInt16 = 53
    private static let deleteKeyCode: UInt16 = 51

    private(set) var rules: [DisplaySwapRule] = []
    private(set) var displays: [ConnectedDisplay] = []
    private(set) var isTrusted = false
    private(set) var recordingRuleID: UUID?
    /// 快捷鍵已被其他 App 註冊走、這裡註冊不到的組合。
    private(set) var conflictedRuleIDs: Set<UUID> = []
    private(set) var isSwapping = false
    private(set) var animates = true
    private(set) var canCaptureScreen = false
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let service = DisplaySwapService.shared
    @ObservationIgnored private let snapshotService = WindowSnapshotService.shared
    @ObservationIgnored private let overlay = DisplaySwapOverlay()
    @ObservationIgnored private let hotKeys = GlobalHotKeys()
    @ObservationIgnored private var keyMonitor: Any?
    @ObservationIgnored private var screenObserver: NSObjectProtocol?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        animates = defaults.object(forKey: Self.animatesKey) as? Bool ?? true
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
        warmUpCapture()
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
        canCaptureScreen = snapshotService.hasPermission()
    }

    /// 截圖功能第一次用要多花約 0.2 秒啟動，App 開著時先暖好，第一次按快捷鍵才不會特別慢。
    private func warmUpCapture() {
        guard animates, snapshotService.hasPermission() else { return }
        let service = snapshotService
        Task.detached(priority: .background) {
            await service.warmUp()
        }
    }

    func setAnimates(_ enabled: Bool) {
        animates = enabled
        defaults.set(enabled, forKey: Self.animatesKey)
        if enabled && !snapshotService.hasPermission() {
            requestScreenCapture()
        }
    }

    func requestScreenCapture() {
        canCaptureScreen = snapshotService.requestPermission()
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
        let plan = await Task.detached {
            service.plan(first, second, excluding: ownPID)
        }.value
        guard !plan.moves.isEmpty else { return }

        await showOverlay(for: plan, displays: [first, second])
        let result = await Task.detached {
            service.execute(plan)
        }.value
        if overlay.isShowing {
            try? await Task.sleep(for: Self.redrawDelay)
            await overlay.dismiss()
        }
        errorMessage = result.failed > 0 ? "\(result.failed) 個視窗搬不動" : nil
    }

    /// 截圖失敗或沒有權限時不蓋，直接搬，互換本身不受影響。
    /// 動畫播完才搬真的視窗：同時搬的話視窗伺服器忙不過來，動畫會掉格、最後直接跳到終點（2026-10-13 錄影實測）。
    /// 搬動期間覆蓋層停在最終畫面，看起來已經換好了。
    private func showOverlay(for plan: DisplaySwapPlan, displays: [ConnectedDisplay]) async {
        guard animates, snapshotService.hasPermission() else { return }
        let snapshots: DisplaySnapshots
        do {
            snapshots = try await snapshotService.capture(displays: displays, hiding: Set(plan.moves.map(\.windowNumber)))
        } catch {
            Self.logger.error("截圖失敗，改為直接搬：\(error.localizedDescription, privacy: .public)")
            return
        }
        overlay.show(
            displays: displays,
            backgrounds: snapshots.backgrounds,
            snapshots: plan.moves.compactMap { move in
                snapshots.window(move.from, on: displays).map {
                    DisplaySwapOverlay.Snapshot(image: $0, order: move.order, from: move.from, to: move.to)
                }
            }
        )
        // 先讓蓋上去的那一格畫出來，再開始動畫。
        try? await Task.sleep(for: .milliseconds(16))
        await overlay.animate()
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
