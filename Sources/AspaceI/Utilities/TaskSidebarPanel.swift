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
        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return }
        let cocoaFrame = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
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

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }
}
