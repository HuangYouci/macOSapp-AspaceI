import AppKit

/// 螢幕全黑的覆蓋視窗。每個螢幕各一個（「每個螢幕有獨立桌面空間」開著時一個視窗跨不了兩個螢幕），
/// 放在螢幕保護程式那一層，選單列、Dock、全螢幕 App 都蓋得住。
@MainActor
final class BlackoutOverlay {
    private var windows: [NSWindow] = []

    var isShowing: Bool { !windows.isEmpty }

    func show() {
        dismiss()
        let level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        for screen in NSScreen.screens {
            let window = KeyableWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = level
            window.backgroundColor = .black
            window.isOpaque = true
            window.hasShadow = false
            window.isReleasedWhenClosed = false
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
            windows.append(window)
        }
        // 成為 key window，鍵盤事件才會先進到 AspaceI，不會打進底下的 App。
        windows.first?.makeKey()
    }

    func dismiss() {
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
    }
}

/// 無邊框視窗預設不能成為 key window。
private final class KeyableWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}
