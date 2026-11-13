import AppKit
import CoreImage
import CoreMedia
import ScreenCaptureKit

nonisolated private struct AreaCaptureStreamSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

struct AreaCaptureLatestFrame<Value> {
    private(set) var value: Value?
    private(set) var presentationTime: TimeInterval?

    mutating func receive(_ value: Value, presentedAt time: TimeInterval) {
        guard time.isFinite, time >= 0, time >= (presentationTime ?? 0) else { return }
        self.value = value
        presentationTime = time
    }

    func frame(atOrBefore time: TimeInterval) -> Value? {
        guard time.isFinite, let presentationTime, presentationTime <= time else { return nil }
        return value
    }
}

@MainActor
final class AreaCaptureFrameStream: NSObject, SCStreamOutput, SCStreamDelegate {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    private var stream: SCStream?
    private var latest = AreaCaptureLatestFrame<CMSampleBuffer>()
    private var acceptingFrames = true
    private var stoppedBySystem = false
    private let didUpdate: () -> Void
    private let didFail: (Error) -> Void
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    var isReady: Bool { latest.value != nil }

    init(displayID: CGDirectDisplayID, frame: CGRect, didUpdate: @escaping () -> Void, didFail: @escaping (Error) -> Void) {
        self.displayID = displayID
        self.frame = frame
        self.didUpdate = didUpdate
        self.didFail = didFail
    }

    func start(display: SCDisplay, excluding application: SCRunningApplication, covers: [SCWindow]) async throws {
        let filter = SCContentFilter(display: display, excludingApplications: [application], exceptingWindows: covers)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = false
        configuration.minimumFrameInterval = .zero
        configuration.queueDepth = 3
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
        NSLog("Area capture stream started: display=%u excludedApplication=%d wallpaperCovers=%ld", displayID, application.processID, covers.count)
    }

    func snapshot(atOrBefore eventTime: TimeInterval) throws -> AreaCaptureSnapshot {
        guard let sample = latest.frame(atOrBefore: eventTime), let time = latest.presentationTime else {
            NSLog("Area capture frame rejected: display=%u selectionTime=%.6f latestPresentationTime=%.6f",
                  displayID, eventTime, latest.presentationTime ?? -1)
            throw CocoaError(.fileReadUnknown)
        }
        return AreaCaptureSnapshot(displayID: displayID, frame: frame, image: try Self.image(from: sample), presentationTime: time)
    }

    func magnifierImage(at point: CGPoint, geometry: AreaCaptureSnapshot) -> CGImage? {
        guard let sample = latest.value, let buffer = CMSampleBufferGetImageBuffer(sample) else { return nil }
        let pixels = geometry.magnifierPixelRect(at: point)
        let image = CIImage(cvPixelBuffer: buffer)
        let region = CGRect(x: pixels.minX, y: image.extent.height - pixels.maxY, width: pixels.width, height: pixels.height)
        return Self.imageContext.createCGImage(image, from: region)
    }

    func stop() async throws {
        acceptingFrames = false
        guard let stream else { return }
        defer {
            try? stream.removeStreamOutput(self, type: .screen)
            self.stream = nil
            latest = AreaCaptureLatestFrame()
        }
        if !stoppedBySystem {
            do {
                try await stream.stopCapture()
            } catch {
                NSLog("Area capture stream stop failed: display=%u error=%@", displayID, error.localizedDescription)
                throw error
            }
        }
        NSLog("Area capture stream stopped: display=%u", displayID)
    }

    static func image(from sample: CMSampleBuffer) throws -> CGImage {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw CocoaError(.fileReadCorruptFile) }
        let image = CIImage(cvPixelBuffer: buffer)
        guard let result = imageContext.createCGImage(image, from: image.extent) else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

    static func presentationTime(of sample: CMSampleBuffer) -> TimeInterval? {
        let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
        if let ticks = attachments?.first?[.displayTime] as? NSNumber, ticks.uint64Value > 0 {
            return CMClockMakeHostTimeFromSystemUnits(ticks.uint64Value).seconds
        }
        let time = CMSampleBufferGetPresentationTimeStamp(sample)
        return time.isNumeric && time.seconds >= 0 ? time.seconds : nil
    }

    nonisolated func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let sample = AreaCaptureStreamSample(buffer: sampleBuffer)
        MainActor.assumeIsolated {
            let sampleBuffer = sample.buffer
            guard acceptingFrames, type == .screen, sampleBuffer.isValid,
                  let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let status = attachments.first?[.status] as? Int else { return }
            if status == SCFrameStatus.blank.rawValue || status == SCFrameStatus.suspended.rawValue || status == SCFrameStatus.stopped.rawValue {
                acceptingFrames = false
                didFail(CocoaError(.fileReadUnknown))
                return
            }
            guard status == SCFrameStatus.complete.rawValue, let time = Self.presentationTime(of: sampleBuffer) else { return }
            latest.receive(sampleBuffer, presentedAt: time)
            didUpdate()
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            stoppedBySystem = true
            guard acceptingFrames else { return }
            NSLog("Area capture stream failed: display=%u error=%@", displayID, error.localizedDescription)
            didFail(error)
        }
    }
}
