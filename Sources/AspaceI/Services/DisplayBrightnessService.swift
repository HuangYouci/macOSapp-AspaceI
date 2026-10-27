import CoreGraphics
import Darwin
import os

/// 讀寫螢幕背光亮度。公開 API 沒有這個能力，走系統私有的 DisplayServices（MonitorControl 等工具同樣做法），
/// 執行期用 `dlsym` 取函式，取不到就當作不能調。只對內建螢幕有效，外接螢幕要走 DDC，這裡不處理。
@MainActor
final class DisplayBrightnessService {
    static let shared = DisplayBrightnessService()

    private typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "Brightness")
    private let getBrightness: GetBrightness?
    private let setBrightness: SetBrightness?

    private init() {
        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
            Self.logger.error("載入 DisplayServices 失敗")
            getBrightness = nil
            setBrightness = nil
            return
        }
        getBrightness = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetBrightness.self) }
        setBrightness = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetBrightness.self) }
    }

    /// 0...1；不支援調整的螢幕回傳 nil。
    func brightness(of displayID: CGDirectDisplayID) -> Float? {
        guard let getBrightness else { return nil }
        var value: Float = 0
        let status = getBrightness(displayID, &value)
        guard status == 0 else { return nil }
        return value
    }

    @discardableResult
    func setBrightness(_ value: Float, of displayID: CGDirectDisplayID) -> Bool {
        guard let setBrightness else { return false }
        let status = setBrightness(displayID, min(max(value, 0), 1))
        if status != 0 {
            Self.logger.error("設定螢幕 \(displayID) 亮度失敗：\(status)")
        }
        return status == 0
    }
}
