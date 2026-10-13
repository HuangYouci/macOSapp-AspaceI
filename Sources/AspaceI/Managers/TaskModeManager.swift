import AppKit
import Observation
import os

/// 任務管理：在選定的螢幕上，左邊側欄列出所有 AI 工具的視窗（即時縮圖、名稱、額度），
/// 右邊工作區放選中的那個。所有接手的視窗都調成工作區大小疊在一起，切換只是把那個拉到最前面。
/// 結束時把視窗放回開始前的位置。
@MainActor
@Observable
final class TaskModeManager {
    private static let displayKey = "taskModeDisplay"
    private static let shortcutKey = "taskModeShortcut"
    private static let hotKeyID = UUID(uuidString: "7A5C0DE0-0000-4000-8000-000000000001") ?? UUID()
    /// 新開的視窗、切換、關掉的視窗最慢這麼久會反映到側欄。
    private static let refreshInterval: Duration = .milliseconds(1500)
    private static let thumbnailPointWidth: CGFloat = 200
    /// 點側欄後，系統的視窗疊放順序要一會兒才跟上；這段期間以點的為準，不讓重掃把選取搶回舊視窗。
    private static let selectionHold: Duration = .milliseconds(1500)
    private static let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "TaskMode")

    private(set) var isActive = false
    private(set) var isChanging = false
    private(set) var display: DisplayReference?
    private(set) var displays: [ConnectedDisplay] = []
    private(set) var shortcut: KeyShortcut?
    private(set) var isRecording = false
    private(set) var shortcutConflicted = false
    private(set) var isTrusted = false
    private(set) var canCaptureScreen = false
    private(set) var windows: [TaskWindow] = []
    private(set) var sidebarItems: [TaskSidebarView.Item] = []
    private(set) var selectedID: CGWindowID?
    /// 每個視窗一個盒子，新畫面只寫進盒子：只有那張縮圖重畫，不會每秒好幾次把整個側欄重畫。
    private(set) var thumbnails: [CGWindowID: Thumbnail] = [:]
    var errorMessage: String?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let displayService = DisplaySwapService.shared
    @ObservationIgnored private let windowService = TaskWindowService.shared
    @ObservationIgnored private let snapshotService = WindowSnapshotService.shared
    @ObservationIgnored private let recorder = ShortcutRecorder()
    @ObservationIgnored private let panel = TaskSidebarPanel()
    @ObservationIgnored private var capturer: WindowThumbnailCapturer?
    @ObservationIgnored private var instances: InstanceManager?
    @ObservationIgnored private var accounts: AccountManager?
    @ObservationIgnored private var activeDisplay: ConnectedDisplay?
    @ObservationIgnored private var elements: [CGWindowID: AXUIElement] = [:]
    @ObservationIgnored private var originalFrames: [CGWindowID: CGRect] = [:]
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var screenObserver: NSObjectProtocol?
    @ObservationIgnored private var pendingSelection: (id: CGWindowID, until: ContinuousClock.Instant)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        display = Self.decode(DisplayReference.self, from: defaults.data(forKey: Self.displayKey))
        shortcut = Self.decode(KeyShortcut.self, from: defaults.data(forKey: Self.shortcutKey))
        capturer = WindowThumbnailCapturer { [weak self] id, image in
            guard let self, isActive else { return }
            if let box = thumbnails[id] {
                box.image = image
            } else {
                thumbnails[id] = Thumbnail(image: image)
            }
        }
    }

    func start(instances: InstanceManager, accounts: AccountManager) {
        guard screenObserver == nil else { return }
        self.instances = instances
        self.accounts = accounts
        refreshDisplays()
        refreshPermissions()
        registerHotKey()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        }
    }

    func refreshDisplays() {
        displays = displayService.connectedDisplays()
    }

    func refreshPermissions() {
        isTrusted = displayService.isTrusted(prompt: false)
        canCaptureScreen = snapshotService.hasPermission()
    }

    func requestTrust() {
        isTrusted = displayService.isTrusted(prompt: true)
    }

    func requestScreenCapture() {
        canCaptureScreen = snapshotService.requestPermission()
    }

    /// 沒選過或選的螢幕沒接上時用主螢幕。
    var resolvedDisplay: ConnectedDisplay? {
        if let display, let found = displays.first(where: { $0.uuid == display.uuid }) {
            return found
        }
        return displays.first
    }

    func setDisplay(_ reference: DisplayReference) {
        display = reference
        save(reference, forKey: Self.displayKey)
    }

    // MARK: 快捷鍵

    func startRecording() {
        recorder.stop()
        isRecording = true
        recorder.start { [weak self] outcome in
            guard let self else { return }
            isRecording = false
            switch outcome {
            case .recorded(let shortcut): setShortcut(shortcut)
            case .cleared: setShortcut(nil)
            case .cancelled: break
            }
        }
    }

    func stopRecording() {
        recorder.stop()
    }

    func setShortcut(_ shortcut: KeyShortcut?) {
        self.shortcut = shortcut
        if let shortcut {
            save(shortcut, forKey: Self.shortcutKey)
        } else {
            defaults.removeObject(forKey: Self.shortcutKey)
        }
        registerHotKey()
    }

    private func registerHotKey() {
        let items: [GlobalHotKeys.Item] = shortcut.map { shortcut in
            [(Self.hotKeyID, shortcut, { [weak self] in
                Task { await self?.toggle() }
            })]
        } ?? []
        shortcutConflicted = !GlobalHotKeys.shared.set("taskMode", items).isEmpty
    }

    // MARK: 開關

    func toggle() async {
        if isActive {
            await deactivate()
        } else {
            await activate()
        }
    }

    func activate() async {
        guard !isActive, !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        refreshDisplays()
        refreshPermissions()
        guard isTrusted else {
            requestTrust()
            fail("需要輔助使用權限")
            return
        }
        guard let target = resolvedDisplay else {
            fail("沒有可用的螢幕")
            return
        }
        // 縮圖要螢幕錄製權限，沒有也能用，只是側欄只有圖示。不在這裡要權限：
        // 每次開啟都跳出系統設定會打斷使用者，而且開啟流程會卡到系統設定關掉，這段期間的快捷鍵都被忽略。
        activeDisplay = target
        isActive = true
        errorMessage = nil
        await instances?.refreshRunning()
        panel.show(frame: TaskModeLayout.sidebarFrame(in: target.visibleFrame), content: TaskSidebarHost(manager: self))
        await refresh()
        if let front = windows.first?.id {
            select(front)
        }
        observeWorkspace()
        startRefreshLoop()
    }

    func deactivate() async {
        guard isActive, !isChanging else { return }
        isChanging = true
        defer { isChanging = false }
        isActive = false
        refreshTask?.cancel()
        refreshTask = nil
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers = []
        panel.hide()
        await capturer?.stopAll()

        let moves = windows.compactMap { window -> (element: AXUIElement, from: CGRect, to: CGRect, id: CGWindowID)? in
            guard let element = elements[window.id], let original = originalFrames[window.id] else { return nil }
            return (element, window.frame, original, window.id)
        }
        let service = windowService
        let box = TaskMoves(moves: moves)
        _ = await Task.detached { service.place(box.moves) }.value

        windows = []
        sidebarItems = []
        thumbnails = [:]
        elements = [:]
        originalFrames = [:]
        selectedID = nil
        activeDisplay = nil
    }

    /// 把視窗拉到最前面並把它的 App 叫到前景，鍵盤輸入才會進去。
    /// 選取框先換過去；拉視窗走 Accessibility，App 回應慢時會等，放到背景做，側欄才不會凍住。
    func select(_ id: CGWindowID) {
        guard let element = elements[id], let window = windows.first(where: { $0.id == id }) else { return }
        selectedID = id
        pendingSelection = (id, .now + Self.selectionHold)
        let box = RaiseTarget(element: element)
        let pid = window.pid
        Task.detached {
            AXWindow.raise(box.element)
            await MainActor.run {
                _ = NSRunningApplication(processIdentifier: pid)?.activate()
            }
        }
    }

    // MARK: 更新

    private func startRefreshLoop() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { return }
                await self?.refresh()
            }
        }
    }

    /// App 開關後程序編號要重新判定（`ps`，在背景跑），切換 App 時馬上更新選中的那格。
    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    do {
                        // 剛啟動的 App 還沒開出視窗，稍等再判定。
                        try await Task.sleep(for: .seconds(1))
                    } catch {
                        return
                    }
                    await self?.instances?.refreshRunning()
                    await self?.refresh()
                }
            })
        }
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        })
    }

    private var isRefreshing = false

    private func refresh() async {
        guard isActive, !isRefreshing, let display = activeDisplay, let instances else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let pids = Set(instances.runningProcessIDs.values.flatMap { $0 })
        let service = windowService
        let scan = await Task.detached { service.scan(pids: pids) }.value
        guard isActive else { return }

        let known = Set(elements.keys)
        let target = TaskModeLayout.mainFrame(in: display.visibleFrame)
        let arrived = scan.windows.filter { !known.contains($0.id) }
        for window in arrived {
            originalFrames[window.id] = window.frame
        }
        elements = scan.elements
        // 內容沒變就不重設：觀察到的屬性一被寫入，整個側欄就會重畫。
        if windows != scan.windows {
            windows = scan.windows
        }
        let current = Set(scan.windows.map(\.id))
        originalFrames = originalFrames.filter { current.contains($0.key) }
        if thumbnails.keys.contains(where: { !current.contains($0) }) {
            thumbnails = thumbnails.filter { current.contains($0.key) }
        }

        // 只把新出現的視窗放進工作區；已經接手的視窗使用者自己挪了就尊重他。
        let moves = arrived.compactMap { window -> (element: AXUIElement, from: CGRect, to: CGRect, id: CGWindowID)? in
            guard window.frame != target, let element = scan.elements[window.id] else { return nil }
            return (element, window.frame, target, window.id)
        }
        if !moves.isEmpty {
            let box = TaskMoves(moves: moves)
            let failed = await Task.detached { service.place(box.moves) }.value
            if !failed.isEmpty {
                Self.logger.notice("\(failed.count) 個視窗搬不進工作區")
            }
            for index in windows.indices where moves.contains(where: { $0.id == windows[index].id }) {
                windows[index].frame = target
            }
        }

        // 視窗清單由前到後排，第一個就是使用者現在看的那個，不論是點側欄還是自己點視窗切過去的。
        // 剛點過側欄時，疊放順序還沒跟上就維持點的那個；跟上了或過了時限才交還給清單。
        let resolved = Self.resolveSelection(front: windows.first?.id, pending: pendingSelection, now: .now, current: current)
        if !resolved.keepsPending {
            pendingSelection = nil
        }
        let selection = resolved.selection
        if selectedID != selection {
            selectedID = selection
        }
        let items = makeItems()
        if sidebarItems != items {
            sidebarItems = items
        }
        if canCaptureScreen {
            await capturer?.update(windowIDs: current, pixelWidth: Int(Self.thumbnailPointWidth * display.scale))
        }
    }

    // MARK: 螢幕互換

    /// 互換牽涉到任務管理所在的螢幕時，螢幕互換要一起處理的東西：側欄面板滑過去，工作區的視窗落在新螢幕的工作區。
    struct SwapFollow {
        let sidebar: PlannedWindowMove?
        let targets: [CGWindowID: CGRect]
    }

    /// 互換沒有牽涉到任務管理所在的螢幕、或任務管理沒開時是 nil。
    func swapFollow(_ first: ConnectedDisplay, _ second: ConnectedDisplay) -> SwapFollow? {
        guard isActive, !isChanging, let current = activeDisplay,
              let destination = Self.destination(of: current, first, second) else { return nil }
        let frames = Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) })
        let sidebar = panel.windowID.map {
            PlannedWindowMove(
                windowNumber: $0,
                order: -1,
                from: TaskModeLayout.sidebarFrame(in: current.visibleFrame),
                to: TaskModeLayout.sidebarFrame(in: destination.visibleFrame)
            )
        }
        return SwapFollow(
            sidebar: sidebar,
            targets: TaskModeLayout.workspaceTargets(frames, from: current.visibleFrame, to: destination.visibleFrame)
        )
    }

    /// 視窗已經搬好之後呼叫：側欄移到新螢幕，之後新開的視窗也放進新螢幕的工作區。
    /// 只換這次開啟用的螢幕，設定裡選的螢幕不動，下次開啟仍在設定的那個。
    func didSwap(_ first: ConnectedDisplay, _ second: ConnectedDisplay) async {
        guard isActive, let current = activeDisplay,
              let destination = Self.destination(of: current, first, second) else { return }
        activeDisplay = destination
        panel.move(to: TaskModeLayout.sidebarFrame(in: destination.visibleFrame))
        originalFrames = TaskModeLayout.swappedFrames(
            originalFrames,
            screens: [first.frame, second.frame],
            visible: [first.visibleFrame, second.visibleFrame]
        )
        await refresh()
    }

    private static func destination(of current: ConnectedDisplay, _ first: ConnectedDisplay, _ second: ConnectedDisplay) -> ConnectedDisplay? {
        switch current.uuid {
        case first.uuid: second
        case second.uuid: first
        default: nil
        }
    }

    private func screensChanged() {
        refreshDisplays()
        guard isActive, let activeDisplay else { return }
        if !displays.contains(where: { $0.uuid == activeDisplay.uuid }) {
            Task { await deactivate() }
        }
    }

    /// 側欄依平台與名稱固定排序：依疊放順序排的話，每切換一次整排就跳一次。
    private func makeItems() -> [TaskSidebarView.Item] {
        guard let instances, let accounts else { return [] }
        var instanceByPID: [pid_t: Instance] = [:]
        for instance in instances.groups.flatMap(\.all) {
            for pid in instances.runningProcessIDs[instance.id] ?? [] {
                instanceByPID[pid] = instance
            }
        }
        let order = InstanceManager.groupOrder
        return windows.compactMap { window -> TaskSidebarView.Item? in
            guard let instance = instanceByPID[window.pid] else { return nil }
            let account = instances.currentAccount(for: instance, accounts: accounts)
            let name = account?.label ?? (instances.isDefault(instance) ? instance.platform.clientName : instance.name)
            return TaskSidebarView.Item(
                id: window.id,
                platform: instance.platform,
                name: name,
                quota: Self.quotaText(account),
                title: window.title
            )
        }
        .sorted {
            let lhs = (order.firstIndex(of: $0.platform) ?? 0, $0.name, $0.id)
            let rhs = (order.firstIndex(of: $1.platform) ?? 0, $1.name, $1.id)
            return lhs < rhs
        }
    }

    /// 剛點過側欄時以點的為準；最上層已經是它、時限到了、或它被關掉了，才交還給疊放順序。
    static func resolveSelection(
        front: CGWindowID?,
        pending: (id: CGWindowID, until: ContinuousClock.Instant)?,
        now: ContinuousClock.Instant,
        current: Set<CGWindowID>
    ) -> (selection: CGWindowID?, keepsPending: Bool) {
        guard let pending, front != pending.id, now < pending.until, current.contains(pending.id) else {
            return (front, false)
        }
        return (pending.id, true)
    }

    static func quotaText(_ account: Account?) -> String {
        let parts = (account?.quota?.primaryWindows ?? [])
            .filter { $0.kind != .other }
            .map { "\($0.kind.shortTitle) \($0.remainingPercentage)%" }
        return parts.isEmpty ? "--" : parts.joined(separator: " · ")
    }

    // MARK: 共用

    /// 快捷鍵觸發時 popup 通常沒開，看不到訊息，所以同時發出提示音。
    private func fail(_ message: String) {
        errorMessage = message
        NSSound.beep()
    }

    private func save(_ value: some Encodable, forKey key: String) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            logger.error("讀取任務管理設定失敗：\(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

extension TaskModeManager {
    @MainActor
    @Observable
    final class Thumbnail {
        var image: CGImage

        init(image: CGImage) {
            self.image = image
        }
    }
}

/// Accessibility 物件沒有標 Sendable，包一層交給背景拉到最前面。
private struct RaiseTarget: @unchecked Sendable {
    let element: AXUIElement
}

/// Accessibility 物件沒有標 Sendable，包一層交給背景搬動。
private struct TaskMoves: @unchecked Sendable {
    let moves: [(element: AXUIElement, from: CGRect, to: CGRect, id: CGWindowID)]
}
