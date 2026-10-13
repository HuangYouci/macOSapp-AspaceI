import Carbon.HIToolbox

/// 系統層級快捷鍵。用 Carbon 的 `RegisterEventHotKey`：不需要輔助使用權限，AspaceI 不在前景也收得到。
/// 全 App 共用一份，各功能用自己的群組登記；同一組按鍵只有先登記的那個拿得到。
@MainActor
final class GlobalHotKeys {
    typealias Item = (id: UUID, shortcut: KeyShortcut, action: () -> Void)

    static let shared = GlobalHotKeys()
    /// 'ASPI'，區分這是 AspaceI 註冊的熱鍵。
    private static let signature: OSType = 0x4153_5049

    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]
    private var groups: [String: [Item]] = [:]
    private var failed: Set<UUID> = []
    private var isSuspended = false

    /// 換掉一個群組的熱鍵。回傳這個群組註冊失敗的項目（通常是被其他 App 或另一個群組先註冊走）。
    func set(_ group: String, _ items: [Item]) -> Set<UUID> {
        groups[group] = items
        registerAll()
        return failed.intersection(items.map(\.id))
    }

    /// 錄製快捷鍵時先全部撤掉：已註冊的按鍵會被系統直接攔走，錄不進來。
    func suspend() {
        isSuspended = true
        unregisterAll()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        registerAll()
    }

    private func registerAll() {
        unregisterAll()
        guard !isSuspended else { return }
        installHandlerIfNeeded()
        failed = []
        var nextID: UInt32 = 1
        for group in groups.keys.sorted() {
            for item in groups[group] ?? [] {
                let hotKeyID = EventHotKeyID(signature: Self.signature, id: nextID)
                nextID += 1
                var ref: EventHotKeyRef?
                let status = RegisterEventHotKey(item.shortcut.keyCode, item.shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
                guard status == noErr, let ref else {
                    failed.insert(item.id)
                    continue
                }
                registered.append(ref)
                actions[hotKeyID.id] = item.action
            }
        }
    }

    private func unregisterAll() {
        for ref in registered {
            UnregisterEventHotKey(ref)
        }
        registered = []
        actions = [:]
    }

    private func fire(_ id: UInt32) {
        actions[id]?()
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // 這個物件跟著 App 活到結束，不會比處理器先釋放，傳未保留的指標即可。
        let owner = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr, hotKeyID.signature == GlobalHotKeys.signature else { return OSStatus(eventNotHandledErr) }
            let hotKeys = Unmanaged<GlobalHotKeys>.fromOpaque(userData).takeUnretainedValue()
            // Carbon 事件在主執行緒派送。
            MainActor.assumeIsolated {
                hotKeys.fire(hotKeyID.id)
            }
            return noErr
        }, 1, &spec, owner, &handler)
    }
}
