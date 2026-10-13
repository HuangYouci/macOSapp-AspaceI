import CoreGraphics

/// 螢幕互換的座標換算。全部使用左上角為原點、y 向下的全域座標（與 Accessibility、`CGDisplayBounds` 相同）。
enum DisplaySwapGeometry {
    /// 視窗與哪個區域重疊面積最大就算在哪裡；跨螢幕的視窗不以中心點判斷，避免剛好壓在邊界時歸錯邊。
    static func index(of frame: CGRect, in areas: [CGRect]) -> Int? {
        var best: (index: Int, area: CGFloat)?
        for (index, area) in areas.enumerated() {
            let overlap = frame.intersection(area)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let size = overlap.width * overlap.height
            if best == nil || size > (best?.area ?? 0) {
                best = (index, size)
            }
        }
        return best?.index
    }

    /// 依兩個可用區域（扣掉選單列與 Dock）的比例換算位置與大小，佔滿的視窗換過去仍是佔滿。
    /// 結果一律收進目標區域內，原本有一部分超出螢幕的視窗也會被拉回來。
    static func mapped(_ frame: CGRect, from source: CGRect, to target: CGRect) -> CGRect {
        guard source.width > 0, source.height > 0 else { return frame }
        let scaleX = target.width / source.width
        let scaleY = target.height / source.height
        let width = min(frame.width * scaleX, target.width)
        let height = min(frame.height * scaleY, target.height)
        var x = target.minX + (frame.minX - source.minX) * scaleX
        var y = target.minY + (frame.minY - source.minY) * scaleY
        x = min(max(x, target.minX), target.maxX - width)
        y = min(max(y, target.minY), target.maxY - height)
        return CGRect(x: x.rounded(), y: y.rounded(), width: width.rounded(), height: height.rounded())
    }

    /// 在兩個螢幕之間互換：先把兩邊的視窗都分好再換算，搬過去的視窗不會再被搬回來。
    /// `screens` 是各螢幕的完整範圍（用來判斷視窗在哪），`visible` 是對應的可用區域（用來換算）。
    static func plan(
        windows: [CGRect],
        screens: [CGRect],
        visible: [CGRect],
        first: Int,
        second: Int
    ) -> [Int: CGRect] {
        var moves: [Int: CGRect] = [:]
        for (windowIndex, frame) in windows.enumerated() {
            switch index(of: frame, in: screens) {
            case first:
                moves[windowIndex] = mapped(frame, from: visible[first], to: visible[second])
            case second:
                moves[windowIndex] = mapped(frame, from: visible[second], to: visible[first])
            default:
                continue
            }
        }
        return moves
    }
}
