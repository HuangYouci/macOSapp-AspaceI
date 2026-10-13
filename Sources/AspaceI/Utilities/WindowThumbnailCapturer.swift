import CoreImage
import CoreMedia
import os
import ScreenCaptureKit

/// 任務管理側欄的即時縮圖：每個視窗一條 ScreenCaptureKit 串流，小尺寸、每秒幾格，被別的視窗蓋住也照樣拿得到畫面。
/// 需要「螢幕錄製」權限；沒有權限時不開串流，側欄只顯示平台圖示。
@MainActor
final class WindowThumbnailCapturer {
    /// 每秒幾格。縮圖只是讓人認得出是哪個視窗、看得到在跑，太高只是白耗電。
    private static let framesPerSecond: Int32 = 3
    private static let logger = Logger(subsystem: "com.huangyouci.AspaceI", category: "TaskMode")

    private var streams: [CGWindowID: (stream: SCStream, output: ThumbnailOutput)] = [:]
    private var pending: Set<CGWindowID> = []
    private let onFrame: (CGWindowID, CGImage) -> Void

    init(onFrame: @escaping (CGWindowID, CGImage) -> Void) {
        self.onFrame = onFrame
    }

    /// 開好還沒有串流的視窗，關掉已經不在清單裡的。
    func update(windowIDs: Set<CGWindowID>, pixelWidth: Int) async {
        for id in streams.keys where !windowIDs.contains(id) {
            await stop(id)
        }
        let missing = windowIDs.subtracting(streams.keys).subtracting(pending)
        guard !missing.isEmpty else { return }
        pending.formUnion(missing)
        defer { pending.subtract(missing) }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            Self.logger.error("取得視窗清單失敗：\(error.localizedDescription, privacy: .public)")
            return
        }
        for window in content.windows where missing.contains(window.windowID) {
            await start(window, pixelWidth: pixelWidth)
        }
    }

    func stopAll() async {
        for id in Array(streams.keys) {
            await stop(id)
        }
    }

    private func start(_ window: SCWindow, pixelWidth: Int) async {
        let configuration = SCStreamConfiguration()
        let aspect = window.frame.height / max(window.frame.width, 1)
        configuration.width = pixelWidth
        configuration.height = max(Int(CGFloat(pixelWidth) * aspect), 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.scalesToFit = true
        configuration.preservesAspectRatio = true

        let id = window.windowID
        let output = ThumbnailOutput(id: id) { [weak self] id, image in
            Task { @MainActor in self?.onFrame(id, image.value) }
        }
        let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: nil)
        do {
            try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: ThumbnailOutput.queue)
            try await stream.startCapture()
            streams[id] = (stream, output)
        } catch {
            Self.logger.error("縮圖串流開不起來：\(error.localizedDescription, privacy: .public)")
        }
    }

    private func stop(_ id: CGWindowID) async {
        guard let entry = streams.removeValue(forKey: id) else { return }
        do {
            try await entry.stream.stopCapture()
        } catch {
            // 視窗關掉時串流常已自己停了，這裡失敗不影響其他縮圖。
            Self.logger.notice("縮圖串流停止失敗：\(error.localizedDescription, privacy: .public)")
        }
    }
}

/// CGImage 不可變，跨執行緒傳遞是安全的。
struct SendableImage: @unchecked Sendable {
    let value: CGImage
}

/// 收串流畫面並轉成 CGImage。在串流自己的佇列上執行。
private final class ThumbnailOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    static let queue = DispatchQueue(label: "com.huangyouci.AspaceI.thumbnails", qos: .utility)
    private static let context = CIContext()

    private let id: CGWindowID
    private let handler: @Sendable (CGWindowID, SendableImage) -> Void

    init(id: CGWindowID, handler: @escaping @Sendable (CGWindowID, SendableImage) -> Void) {
        self.id = id
        self.handler = handler
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isCompleteFrame(sampleBuffer),
              let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = Self.context.createCGImage(image, from: image.extent) else { return }
        handler(id, SendableImage(value: cgImage))
    }

    /// 畫面沒變時串流也會送「閒置」格，裡面沒有影像。
    private static func isCompleteFrame(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: rawStatus) else { return false }
        return status == .complete
    }
}
