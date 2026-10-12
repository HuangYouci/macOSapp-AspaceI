import SwiftUI

extension View {
    /// 載入中的骨架：灰底加一道掃過的光。
    func shimmering(cornerRadius: CGFloat = 4) -> some View {
        modifier(ShimmerModifier(cornerRadius: cornerRadius))
    }
}

private struct ShimmerModifier: ViewModifier {
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .hidden()
            .overlay {
                TimelineView(.animation) { context in
                    let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.07))
                        .overlay {
                            GeometryReader { proxy in
                                LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: proxy.size.width * 0.6)
                                    .offset(x: (proxy.size.width * 1.6) * phase - proxy.size.width * 0.6)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                }
            }
    }
}
