import AppKit
import SwiftUI

/// 任務管理側欄的浮動面板。點了不會把 AspaceI 叫到前景，焦點留給被選的 AI 視窗。
@MainActor
final class TaskSidebarPanel {
    private static let cornerRadius: CGFloat = 12

    private var panel: NSPanel?

    /// `frame` 用左上角原點的全域座標，這裡換成 AppKit 的座標。
    func show(frame: CGRect, content: some View) {
        hide()
        guard let cocoaFrame = Self.cocoaFrame(frame) else { return }
        let panel = NSPanel(contentRect: cocoaFrame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenNone, .ignoresCycle]

        let background = NSVisualEffectView(frame: CGRect(origin: .zero, size: cocoaFrame.size))
        background.material = .sidebar
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = Self.cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: content)
        hosting.frame = background.bounds
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        panel.setFrame(cocoaFrame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// 螢幕互換時跟著搬過去。只改位置大小，側欄內容與捲動位置不重建。
    func move(to frame: CGRect) {
        guard let panel, let cocoaFrame = Self.cocoaFrame(frame) else { return }
        panel.setFrame(cocoaFrame, display: true)
    }

    /// 視窗清單與 ScreenCaptureKit 用的編號，互換動畫要拿它來截側欄。
    var windowID: CGWindowID? {
        guard let panel, panel.windowNumber > 0 else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    private static func cocoaFrame(_ frame: CGRect) -> CGRect? {
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }
        return CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
    }
}
