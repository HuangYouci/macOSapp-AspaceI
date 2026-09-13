import AppKit
import SwiftUI

extension PlatformKind {
    var logoImage: Image? {
        guard let nsImage = Self.bundledImage(named: rawValue) else { return nil }
        return Image(nsImage: nsImage)
    }

    /// 單色 template 版標誌，給 menu bar 依系統外觀自動上色。
    var glyphImage: NSImage? {
        Self.bundledImage(named: "\(rawValue)-glyph", template: true)
    }

    static var appGlyphImage: NSImage? {
        bundledImage(named: "aspacei-glyph", template: true)
    }

    private static func bundledImage(named name: String, template: Bool = false) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Logos"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.isTemplate = template
        return image
    }
}
