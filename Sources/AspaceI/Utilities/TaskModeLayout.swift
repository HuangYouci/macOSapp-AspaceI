import CoreGraphics

/// 任務管理的版面：左邊窄側欄，右邊是放大的工作區。座標同 Accessibility（左上角原點、y 向下）。
enum TaskModeLayout {
    static let maxSidebarWidth: CGFloat = 220
    /// 側欄最多佔螢幕可用寬度的這個比例，小螢幕上工作區才不會被擠掉太多。
    static let sidebarRatio: CGFloat = 0.2
    static let margin: CGFloat = 8

    static func sidebarWidth(in visible: CGRect) -> CGFloat {
        min(maxSidebarWidth, (visible.width * sidebarRatio).rounded())
    }

    static func sidebarFrame(in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.minX + margin,
            y: visible.minY + margin,
            width: sidebarWidth(in: visible),
            height: visible.height - margin * 2
        )
    }

    static func mainFrame(in visible: CGRect) -> CGRect {
        let left = visible.minX + margin + sidebarWidth(in: visible) + margin
        return CGRect(
            x: left,
            y: visible.minY + margin,
            width: visible.maxX - margin - left,
            height: visible.height - margin * 2
        )
    }
}
