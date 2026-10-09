import AppKit

/// 實例 App 的圖示：原本 App 的圖示右下角疊上與 menu bar 相同的三字短名稱（`ShortLabel`），
/// Dock 上一眼分得出是哪個平台、哪個實例。
enum InstanceIconRenderer {
    @MainActor
    static func icon(base: NSImage, badge: String) -> NSImage {
        let canvas = NSSize(width: 1024, height: 1024)
        return NSImage(size: canvas, flipped: false) { rect in
            base.draw(in: rect)
            guard !badge.isEmpty else { return true }
            let baseFont = NSFont.systemFont(ofSize: 230, weight: .heavy)
            let font = baseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 230) } ?? baseFont
            let text = NSAttributedString(string: badge, attributes: [.font: font, .foregroundColor: NSColor.white])
            let textSize = text.size()
            let height: CGFloat = 330
            // 三個字最寬也不超過圖示寬度，否則左邊會被裁掉。
            let width = min(rect.width - 48, max(height, textSize.width + 110))
            // 系統圖示四周約留 100 pt 透明邊，標籤壓在圖示的右下角上。
            let frame = NSRect(x: rect.maxX - width - 24, y: 24, width: width, height: height)
            let capsule = NSBezierPath(roundedRect: frame, xRadius: height / 2, yRadius: height / 2)
            NSColor(white: 0.1, alpha: 0.92).setFill()
            capsule.fill()
            NSColor.white.setStroke()
            capsule.lineWidth = 22
            capsule.stroke()
            text.draw(at: NSPoint(x: frame.midX - textSize.width / 2, y: frame.midY - textSize.height / 2))
            return true
        }
    }
}
