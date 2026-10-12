import SwiftUI

extension View {
    /// 固定在 popup 上緣或下緣的列，捲動區延伸到它底下直到 popup 邊緣。
    /// 內容捲進列底下時由系統的柔和邊緣逐漸模糊淡出，不以實色截斷。
    /// SwiftUI 的 `Material` 與 `NSVisualEffectView(.withinWindow)` 在這裡都模糊不到捲動內容，只會疊一層白（2026-10-12 實測）。
    @ViewBuilder
    func popupBar<Bar: View>(edge: VerticalEdge, @ViewBuilder content: () -> Bar) -> some View {
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, content: content)
                .scrollEdgeEffectStyle(.soft, for: edge == .top ? .top : .bottom)
        } else {
            // 沒有柔和邊緣可用時不讓內容進到列底下，捲動區接在列的邊界。
            VStack(spacing: 0) {
                if edge == .top { content() }
                self
                if edge == .bottom { content() }
            }
        }
    }
}
