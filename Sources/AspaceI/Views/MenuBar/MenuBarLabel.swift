import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let items: [MenuBarQuotaItem]

    var body: some View {
        if let image = renderedImage {
            Image(nsImage: image)
        } else {
            Text("AspaceI")
        }
    }

    /// menu bar 只接受單張圖或文字，因此把多段內容畫成一張 template 圖交給系統上色。
    @MainActor
    private var renderedImage: NSImage? {
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        return image
    }

    private var content: some View {
        HStack(spacing: 6) {
            if items.isEmpty {
                glyph(PlatformKind.appGlyphImage, size: 15)
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Rectangle()
                            .frame(width: 1, height: 11)
                            .opacity(0.45)
                    }
                    HStack(spacing: 3) {
                        glyph(item.platform.glyphImage, size: 12)
                        Text(item.name)
                            .font(.system(size: 11, weight: .medium))
                            .opacity(0.7)
                        Text(item.percentages.joined(separator: " "))
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                    }
                }
            }
        }
        .foregroundStyle(.black)
        .frame(height: 18)
    }

    @ViewBuilder
    private func glyph(_ image: NSImage?, size: CGFloat) -> some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(.template)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}
