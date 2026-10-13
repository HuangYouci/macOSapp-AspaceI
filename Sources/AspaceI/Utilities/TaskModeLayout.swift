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

/// 螢幕互換牽涉到任務管理所在的螢幕時，任務管理跟著換過去。
extension TaskModeLayout {
    /// 掃描與 Accessibility 讀回來的座標可能差到小數點，判斷「還在工作區」時容許的誤差。
    static let workspaceTolerance: CGFloat = 2

    /// 還在工作區裡的視窗直接落在新螢幕的工作區，不照比例換算：兩個螢幕的側欄寬度不一定等比，照比例換會留縫或壓到側欄。
    /// 使用者自己挪過的視窗不在這裡，照一般互換的比例換算。
    static func workspaceTargets(_ frames: [CGWindowID: CGRect], from old: CGRect, to new: CGRect) -> [CGWindowID: CGRect] {
        let source = mainFrame(in: old)
        let target = mainFrame(in: new)
        return frames.filter { isSame($0.value, source) }.mapValues { _ in target }
    }

    /// 結束時要還原的位置也跟著互換，否則一關掉，視窗會回到互換前的那個螢幕。
    static func swappedFrames(_ frames: [CGWindowID: CGRect], screens: [CGRect], visible: [CGRect]) -> [CGWindowID: CGRect] {
        let ids = Array(frames.keys)
        let moves = DisplaySwapGeometry.plan(windows: ids.compactMap { frames[$0] }, screens: screens, visible: visible, first: 0, second: 1)
        var result = frames
        for (index, frame) in moves {
            result[ids[index]] = frame
        }
        return result
    }

    private static func isSame(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) <= workspaceTolerance && abs(lhs.minY - rhs.minY) <= workspaceTolerance
            && abs(lhs.width - rhs.width) <= workspaceTolerance && abs(lhs.height - rhs.height) <= workspaceTolerance
    }
}
