import AppKit
import SwiftUI

/// MenuBarExtra 視窗不吃 `preferredColorScheme`，直接把所屬 NSWindow 固定成淺色外觀。
struct PopupWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.appearance = NSAppearance(named: .aqua)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        nsView.window?.appearance = NSAppearance(named: .aqua)
    }
}
