import SwiftUI

extension TaskSidebarView {
    /// 縮圖獨立成一個 View：縮圖每秒更新好幾次，在自己的 body 裡讀，才只有這一張重畫，
    /// 不會連整個側欄（含選取框）一起重畫而在切換時一頓一頓。
    struct Preview: View {
        let platform: PlatformKind
        let image: () -> CGImage?

        var body: some View {
            if let image = image() {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                PlatformBadge(platform: platform, size: 28)
            }
        }
    }
}
