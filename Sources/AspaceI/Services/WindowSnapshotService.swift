import CoreGraphics
import os
import ScreenCaptureKit

/// 互換動畫用的截圖：每個螢幕一張完整畫面、一張拿掉要搬的視窗後的底圖。只存在記憶體，動畫結束就丟掉。
/// 需要「螢幕錄製」權限。
struct DisplaySnapshots: @unchecked Sendable {
    /// CGImage 不可變，跨執行緒傳遞是安全的。
    var full: [CGDirectDisplayID: CGImage] = [:]
    var backgrounds: [CGDirectDisplayID: CGImage] = [:]

    /// 從視窗所在螢幕的完整畫面切出這個視窗。跟別的視窗重疊的部分會帶到前面視窗的內容，
    /// 但同一個螢幕的視窗搬過去相對位置不變，那一塊會被前面視窗的截圖蓋住，看不出來。
    func window(_ frame: CGRect, on displays: [ConnectedDisplay]) -> CGImage? {
        guard let index = DisplaySwapGeometry.index(of: frame, in: displays.map(\.frame)),
              let image = full[displays[index].displayID] else { return nil }
        let display = displays[index]
        let pixelsPerPoint = CGFloat(image.width) / display.frame.width
        let local = frame.offsetBy(dx: -display.frame.minX, dy: -display.frame.minY)
            .intersection(CGRect(origin: .zero, size: display.frame.size))
        guard !local.isNull, local.width > 0, local.height > 0 else { return nil }
        let pixels = CGRect(
            x: local.minX * pixelsPerPoint,
            y: local.minY * pixelsPerPoint,
            width: local.width * pixelsPerPoint,
            height: local.height * pixelsPerPoint
        ).integral
        return image.cropping(to: pixels)
    }
}

final class WindowSnapshotService: Sendable {
    static let shared = WindowSnapshotService()
    private static let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "DisplaySwap")

    func hasPermission() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// 第一次會跳系統提示；之後只會打開系統設定。允許後要重新開啟 App 才生效。
    func requestPermission() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func warmUp() async {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            Self.logger.notice("截圖暖機失敗：\(error.localizedDescription, privacy: .public)")
        }
    }

    /// 一個視窗一張圖要約 0.2 秒（7 個並行，2026-10-13 實測），整個螢幕一張只要 0.04 秒，所以只截螢幕再切。
    func capture(displays: [ConnectedDisplay], hiding windowNumbers: Set<CGWindowID>) async throws -> DisplaySnapshots {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let hidden = ShareableItem(value: content.windows.filter { windowNumbers.contains($0.windowID) })

        return try await withThrowingTaskGroup(of: DisplaySnapshots.self) { group in
            for display in displays {
                guard let found = content.displays.first(where: { $0.displayID == display.displayID }) else { continue }
                let scDisplay = ShareableItem(value: found)
                for withWindows in [true, false] {
                    group.addTask {
                        let configuration = SCStreamConfiguration()
                        configuration.width = Int(display.frame.width * display.scale)
                        configuration.height = Int(display.frame.height * display.scale)
                        configuration.showsCursor = false
                        let image = try await SCScreenshotManager.captureImage(
                            contentFilter: SCContentFilter(display: scDisplay.value, excludingWindows: withWindows ? [] : hidden.value),
                            configuration: configuration
                        )
                        return withWindows
                            ? DisplaySnapshots(full: [display.displayID: image])
                            : DisplaySnapshots(backgrounds: [display.displayID: image])
                    }
                }
            }
            var merged = DisplaySnapshots()
            for try await part in group {
                merged.full.merge(part.full) { first, _ in first }
                merged.backgrounds.merge(part.backgrounds) { first, _ in first }
            }
            return merged
        }
    }
}

/// ScreenCaptureKit 的視窗與螢幕物件建立後不再變動，但沒有標 Sendable，包一層才能交給各截圖工作。
private struct ShareableItem<Value>: @unchecked Sendable {
    let value: Value
}
