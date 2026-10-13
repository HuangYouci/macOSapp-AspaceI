import Carbon.HIToolbox

/// 系統層級快捷鍵。用 Carbon 的 `RegisterEventHotKey`：不需要輔助使用權限，AspaceI 不在前景也收得到。
@MainActor
final class GlobalHotKeys {
    /// 'ASPI'，區分這是 AspaceI 註冊的熱鍵。
    private static let signature: OSType = 0x4153_5049

    private var handler: EventHandlerRef?
    private var registered: [EventHotKeyRef] = []
    private var actions: [UInt32: () -> Void] = [:]

    /// 整批換掉。回傳註冊失敗的項目編號（通常是被其他 App 先註冊走了）。
    func replaceAll(_ items: [(id: UUID, shortcut: KeyShortcut, action: () -> Void)]) -> Set<UUID> {
        removeAll()
        installHandlerIfNeeded()
        var failed: Set<UUID> = []
        for (index, item) in items.enumerated() {
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index + 1))
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(item.shortcut.keyCode, item.shortcut.modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
            guard status == noErr, let ref else {
                failed.insert(item.id)
                continue
            }
            registered.append(ref)
            actions[hotKeyID.id] = item.action
        }
        return failed
    }

    func removeAll() {
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
