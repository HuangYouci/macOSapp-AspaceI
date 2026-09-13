import SwiftUI

extension View {
    /// popup 內所有卡片共用：白底、圓角、極淡陰影，不畫外框。
    func cardStyle(cornerRadius: CGFloat = 12) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
                .shadow(color: .black.opacity(0.06), radius: 1.5, y: 0.5)
        )
    }
}
