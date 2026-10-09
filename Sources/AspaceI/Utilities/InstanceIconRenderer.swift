import AppKit

/// 實例 App 的圖示：原本 App 的圖示右下角疊上使用者名稱前兩字，Dock 上一眼分得出是哪個平台、哪個實例。
enum InstanceIconRenderer {
    /// 只取字母與數字，`yc.huang` → `YC`、`1-big` → `1B`；全是符號時退回原字串。
    static func badgeText(for name: String) -> String {
        let letters = name.filter { $0.isLetter || $0.isNumber }
        return String((letters.isEmpty ? name : letters).prefix(2)).uppercased()
    }

    @MainActor
    static func icon(base: NSImage, badge: String) -> NSImage {
        let canvas = NSSize(width: 1024, height: 1024)
        return NSImage(size: canvas, flipped: false) { rect in
            base.draw(in: rect)
            guard !badge.isEmpty else { return true }
            let baseFont = NSFont.systemFont(ofSize: 250, weight: .heavy)
            let font = baseFont.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: 250) } ?? baseFont
            let text = NSAttributedString(string: badge, attributes: [.font: font, .foregroundColor: NSColor.white])
            let textSize = text.size()
            let height: CGFloat = 360
            let width = max(height, textSize.width + 130)
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
