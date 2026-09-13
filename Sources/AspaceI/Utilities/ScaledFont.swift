import SwiftUI

/// macOS 不支援 Dynamic Type，popup 字級統一由這裡依系統文字樣式等比放大。
extension Font {
    static let popupScale: CGFloat = 1.2

    static func scaled(_ style: Font.TextStyle, weight: Font.Weight? = nil, design: Font.Design? = nil) -> Font {
        .system(size: baseSize(style) * popupScale, weight: weight ?? (style == .headline ? .bold : .regular), design: design ?? .default)
    }

    static func scaled(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size * popupScale, weight: weight)
    }

    private static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        default: 10
        }
    }
}
