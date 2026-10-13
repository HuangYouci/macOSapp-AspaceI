import AppKit
import QuartzCore

/// 互換動畫。macOS 不能讓別的 App 的視窗平滑移動（逐格改位置會讓每個 App 每一格都重排，又卡又慢），
/// 所以蓋一層和畫面一模一樣的截圖，讓截圖滑過去，真的視窗在底下一次搬好，動畫結束再淡出露出真畫面。
///
/// 每個螢幕各一個覆蓋視窗：「每個螢幕有獨立桌面空間」開著時一個視窗跨不了兩個螢幕。
/// 同一張截圖放進兩個覆蓋視窗、走同一條全域座標路徑，各自只畫得出自己螢幕的那一段，看起來就是一路滑過去。
@MainActor
final class DisplaySwapOverlay {
    struct Snapshot {
        let image: CGImage
        let order: Int
        let from: CGRect
        let to: CGRect
    }

    static let moveDuration: TimeInterval = 0.32
    static let fadeDuration: TimeInterval = 0.14
    private static let cornerRadius: CGFloat = 12

    private var windows: [NSWindow] = []
    private var layers: [(layer: CALayer, content: CALayer, origin: CGPoint, to: CGRect)] = []

    /// 蓋上去的第一格與當下畫面相同，使用者看不出已經蓋了一層。
    func show(displays: [ConnectedDisplay], backgrounds: [CGDirectDisplayID: CGImage], snapshots: [Snapshot]) {
        dismissImmediately()
        // 建立時不要有預設的淡入動畫，否則第一格就和畫面不同。
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        // 疊放順序：後面的視窗先加，前面的蓋在上面。
        let ordered = snapshots.sorted { $0.order > $1.order }
        for display in displays {
            guard let screen = NSScreen.screens.first(where: { Self.displayID(of: $0) == display.displayID }) else { continue }
            let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .floating
            window.isOpaque = true
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.isReleasedWhenClosed = false
            window.sharingType = .none
            window.animationBehavior = .none
            window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
            window.setFrame(screen.frame, display: false)

            // 自己建圖層再交給 view（先設 layer 再開 wantsLayer）。只開 wantsLayer 的話，view 放進視窗之前
            // `view.layer` 還是 nil，加上去的圖層全部沒生效，覆蓋層是空的，動畫照樣跑完卻什麼都看不到。
            let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
            let root = CALayer()
            view.layer = root
            view.wantsLayer = true
            let container = CALayer()
            container.frame = view.bounds
            // 與全域座標相同的 y 向下，換算只要減掉螢幕左上角。
            container.isGeometryFlipped = true
            container.masksToBounds = true
            root.addSublayer(container)

            let background = CALayer()
            background.frame = container.bounds
            background.contents = backgrounds[display.displayID]
            background.contentsGravity = .resize
            background.backgroundColor = NSColor.black.cgColor
            container.addSublayer(background)

            let origin = display.frame.origin
            for snapshot in ordered {
                // 截圖是方的，四角會帶到桌布；裁成圓角，陰影放在外層（裁切會連陰影一起裁掉）。
                let layer = CALayer()
                layer.frame = snapshot.from.offsetBy(dx: -origin.x, dy: -origin.y)
                layer.shadowColor = NSColor.black.cgColor
                layer.shadowOpacity = 0.28
                layer.shadowRadius = 18
                layer.shadowOffset = CGSize(width: 0, height: 8)
                let content = CALayer()
                content.frame = layer.bounds
                content.contents = snapshot.image
                content.contentsGravity = .resize
                content.cornerRadius = Self.cornerRadius
                content.cornerCurve = .continuous
                content.masksToBounds = true
                layer.addSublayer(content)
                container.addSublayer(layer)
                layers.append((layer, content, origin, snapshot.to))
            }

            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    var isShowing: Bool { !windows.isEmpty }

    func animate() async {
        guard !layers.isEmpty else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            CATransaction.begin()
            CATransaction.setAnimationDuration(Self.moveDuration)
            // 先加速再減速。曾用 (0.25, 0.9, 0.3, 1)：前三格就走完八成，剩下一段慢慢爬，看起來像卡住。
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1))
            CATransaction.setCompletionBlock {
                continuation.resume()
            }
            // 內層也要一起改大小，自動縮放不會跟著動畫走。
            for item in layers {
                item.layer.frame = item.to.offsetBy(dx: -item.origin.x, dy: -item.origin.y)
                item.content.frame = CGRect(origin: .zero, size: item.to.size)
            }
            CATransaction.commit()
        }
    }

    func dismiss() async {
        guard !windows.isEmpty else { return }
        let fading = windows
        windows = []
        layers = []
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeDuration
                for window in fading {
                    window.animator().alphaValue = 0
                }
            } completionHandler: {
                continuation.resume()
            }
        }
        for window in fading {
            window.orderOut(nil)
        }
    }

    func dismissImmediately() {
        for window in windows {
            window.orderOut(nil)
        }
        windows = []
        layers = []
    }

    private static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { CGDirectDisplayID($0.uint32Value) }
    }
}
