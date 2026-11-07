import AppKit
import CoreImage
import OSLog
import ScreenCaptureKit

struct SharedWindowFrame {
    let number: UInt64
    fileprivate let buffer: CVPixelBuffer
    fileprivate let content: CGRect
    fileprivate let context: CIContext

    func image(in area: CGRect, windowSize: CGSize) -> CGImage? {
        let scaleX = content.width / windowSize.width
        let scaleY = content.height / windowSize.height
        let pixels = CGRect(x: content.minX + area.minX * scaleX, y: content.minY + area.minY * scaleY,
                            width: area.width * scaleX, height: area.height * scaleY).integral.intersection(content)
        guard !pixels.isEmpty else { return nil }
        let image = CIImage(cvPixelBuffer: buffer)
        let crop = CGRect(x: pixels.minX, y: image.extent.maxY - pixels.maxY, width: pixels.width, height: pixels.height)
        return context.createCGImage(image, from: crop)
    }
}

private final class LatestVideoFrame: NSObject, SCStreamOutput {
    private let lock = NSLock()
    private var frame: SharedWindowFrame?
    private let context = CIContext()
    private let logger = Logger(subsystem: "com.wowforever.konglish.overlay", category: "window-share")

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let buffer = sample.imageBuffer,
              let attachments = (CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
                                 as? [[SCStreamFrameInfo: Any]])?.first,
              let status = attachments[.status] as? Int,
              status == SCFrameStatus.complete.rawValue else { return }
        let surface = CGRect(x: 0, y: 0, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let content: CGRect
        if let encoded = attachments[.contentRect] as? NSDictionary,
           let points = CGRect(dictionaryRepresentation: encoded),
           let scale = attachments[.scaleFactor] as? CGFloat, scale.isFinite, scale > 0 {
            content = points.applying(CGAffineTransform(scaleX: scale, y: scale)).integral.intersection(surface)
            guard !content.isEmpty else { return }
        } else {
            content = surface
        }
        lock.withLock {
            if frame?.content != content {
                logger.notice("Window image \(Int(surface.width))×\(Int(surface.height)); content \(Int(content.minX)),\(Int(content.minY)) \(Int(content.width))×\(Int(content.height))")
            }
            frame = SharedWindowFrame(number: (frame?.number ?? 0) + 1, buffer: buffer, content: content, context: context)
        }
    }

    func snapshot() -> SharedWindowFrame? { lock.withLock { frame } }
}

@MainActor
final class WindowShare: NSObject, SCContentSharingPickerObserver, SCStreamDelegate {
    private let picker = SCContentSharingPicker.shared
    private let latest = LatestVideoFrame()
    private var stream: SCStream?
    private let onChange: (String?) -> Void
    private(set) var windowID: CGWindowID?

    init(onChange: @escaping (String?) -> Void) {
        self.onChange = onChange
    }

    func present() {
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow]
        configuration.allowsChangingSelectedContent = false
        configuration.excludedBundleIDs = NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
            .filter { $0 != "com.blizzard.worldofwarcraft" }
        picker.defaultConfiguration = configuration
        picker.add(self)
        picker.isActive = true
        picker.present(using: .window)
    }

    func close() {
        picker.remove(self)
        picker.isActive = false
    }

    func snapshot() -> SharedWindowFrame? { latest.snapshot() }

    private func start(_ filter: SCContentFilter) async {
        guard #available(macOS 15.2, *),
              filter.includedWindows.count == 1, let window = filter.includedWindows.first,
              let owner = window.owningApplication,
              owner.bundleIdentifier == "com.blizzard.worldofwarcraft" else {
            onChange("World of Warcraft 창을 선택해 주세요.")
            return
        }
        let config = SCStreamConfiguration()
        let scale = max(1, min(2, CGFloat(filter.pointPixelScale)))
        config.width = max(1, Int(window.frame.width * scale))
        config.height = max(1, Int(window.frame.height * scale))
        config.scalesToFit = true
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: 15)
        config.queueDepth = 3
        config.ignoreShadowsSingleWindow = true
        config.showsCursor = false
        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(latest, type: .screen,
                                       sampleHandlerQueue: DispatchQueue(label: "konglish.window-share"))
            try await stream.startCapture()
            self.stream = stream
            windowID = window.windowID
            NSRunningApplication(processIdentifier: owner.processID)?.activate()
            onChange(nil)
        } catch {
            onChange("와우 창을 공유하지 못했어요. 채팅 연결을 다시 눌러 주세요.")
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor in
            guard self.stream == nil else { return }
            await start(filter)
        }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in
            if self.stream == nil { onChange("와우 창 공유가 취소됐어요.") }
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor in onChange("macOS 창 선택을 열지 못했어요.") }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in onChange("와우 창 공유가 끝났어요.") }
    }
}
