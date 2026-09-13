import SwiftUI

struct PlatformBadge: View {
    let platform: PlatformKind
    var size: CGFloat = 24

    var body: some View {
        Group {
            if let logo = platform.logoImage {
                logo
                    .resizable()
                    .scaledToFill()
            } else {
                Text(platform.initials)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(platform.tint)
                    .frame(width: size, height: size)
                    .background(platform.tint.opacity(0.12))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28))
    }
}
