import AppKit

extension NSImage {
    /// SF Symbols 沒有直向的 ellipsis；macOS 的 Menu 標籤只吃圖片，旋轉修飾不會生效，所以先畫成 template 圖。
    static let verticalEllipsis: NSImage = {
        let size = NSSize(width: 4, height: 14)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            let diameter: CGFloat = 3
            for index in 0..<3 {
                let y = rect.minY + 1 + CGFloat(index) * 4.5
                NSBezierPath(ovalIn: NSRect(x: (rect.width - diameter) / 2, y: y, width: diameter, height: diameter)).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }()
}
