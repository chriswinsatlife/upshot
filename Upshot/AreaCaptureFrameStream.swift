import AppKit
import CoreImage
import CoreMedia
import CoreVideo
import Darwin
import ScreenCaptureKit

nonisolated private struct AreaCaptureStreamSample: @unchecked Sendable {
    let buffer: CMSampleBuffer
}

struct AreaCaptureFrameRing<Value> {
    struct Frame {
        let value: Value
        let presentationTime: TimeInterval
    }

    struct Selection {
        let frame: Frame
        let usedOldestFallback: Bool
    }

    let capacity: Int
    private var frames: [Frame?]
    private var oldestIndex = 0
    private(set) var count = 0

    var newest: Frame? { count > 0 ? frames[(oldestIndex + count - 1) % capacity] : nil }
    var oldest: Frame? { count > 0 ? frames[oldestIndex] : nil }

    init(maximumFramesPerSecond: Int = 60) {
        capacity = Int(ceil(Double(max(1, maximumFramesPerSecond)) * 0.25)) + 2
        frames = Array(repeating: nil, count: capacity)
    }

    mutating func receive(_ value: Value, presentedAt time: TimeInterval) {
        guard time.isFinite, time >= 0, time >= (newest?.presentationTime ?? 0) else { return }
        let frame = Frame(value: value, presentationTime: time)
        if newest?.presentationTime == time {
            frames[(oldestIndex + count - 1) % capacity] = frame
        } else if count < capacity {
            frames[(oldestIndex + count) % capacity] = frame
            count += 1
        } else {
            frames[oldestIndex] = frame
            oldestIndex = (oldestIndex + 1) % capacity
        }
    }

    func selection(for eventTime: TimeInterval) -> Selection? {
        guard eventTime.isFinite, count > 0 else { return nil }
        for offset in (0..<count).reversed() {
            if let frame = frames[(oldestIndex + offset) % capacity], frame.presentationTime <= eventTime {
                return Selection(frame: frame, usedOldestFallback: false)
            }
        }
        return oldest.map { Selection(frame: $0, usedOldestFallback: true) }
    }

    mutating func removeAll() {
        frames = Array(repeating: nil, count: capacity)
        oldestIndex = 0
        count = 0
    }
}

final class AreaCaptureFrameBufferPool {
    let maximumBufferCount: Int
    private let pool: CVPixelBufferPool
    private let width: Int
    private let height: Int

    init(width: Int, height: Int, maximumBufferCount: Int) throws {
        self.width = width
        self.height = height
        self.maximumBufferCount = maximumBufferCount
        let attributes: [CFString: Any] = [
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var createdPool: CVPixelBufferPool?
        guard CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &createdPool) == kCVReturnSuccess,
              let createdPool else { throw CocoaError(.fileReadUnknown) }
        pool = createdPool
    }

    func copy(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
        guard CVPixelBufferGetWidth(source) == width, CVPixelBufferGetHeight(source) == height,
              CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else { throw CocoaError(.fileReadCorruptFile) }
        var destination: CVPixelBuffer?
        let attributes = [kCVPixelBufferPoolAllocationThresholdKey: maximumBufferCount] as CFDictionary
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, attributes, &destination) == kCVReturnSuccess,
              let destination else { throw CocoaError(.fileReadUnknown) }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { throw CocoaError(.fileReadUnknown) }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { throw CocoaError(.fileReadUnknown) }
        defer { CVPixelBufferUnlockBaseAddress(destination, []) }
        guard let input = CVPixelBufferGetBaseAddress(source), let output = CVPixelBufferGetBaseAddress(destination) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let inputStride = CVPixelBufferGetBytesPerRow(source)
        let outputStride = CVPixelBufferGetBytesPerRow(destination)
        for row in 0..<height {
            memcpy(output.advanced(by: row * outputStride), input.advanced(by: row * inputStride), width * 4)
        }
        CVBufferPropagateAttachments(source, destination)
        return destination
    }
}

@MainActor
final class AreaCaptureFrameStream: NSObject, SCStreamOutput, SCStreamDelegate {
    let displayID: CGDirectDisplayID
    let frame: CGRect
    private var stream: SCStream?
    private var frames = AreaCaptureFrameRing<CVPixelBuffer>()
    private var frameBufferPool: AreaCaptureFrameBufferPool?
    private var acceptingFrames = true
    private var stoppedBySystem = false
    private var failed = false
    private(set) var windowID: CGWindowID?
    private(set) var windowScale: CGFloat = 1
    private let didUpdate: () -> Void
    private let didFail: (Error) -> Void
    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    var isReady: Bool { frames.count > 0 && !failed }

    init(displayID: CGDirectDisplayID, frame: CGRect, didUpdate: @escaping () -> Void, didFail: @escaping (Error) -> Void) {
        self.displayID = displayID
        self.frame = frame
        self.didUpdate = didUpdate
        self.didFail = didFail
    }

    func start(display: SCDisplay, content: SCShareableContent) async throws {
        let filter = AreaCaptureWindowFilter.displayFilter(display: display, content: content)
        let configuration = SCStreamConfiguration()
        configuration.width = Int(filter.contentRect.width * CGFloat(filter.pointPixelScale))
        configuration.height = Int(filter.contentRect.height * CGFloat(filter.pointPixelScale))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = false
        let maximumFramesPerSecond = max(1, NSScreen.screens.first {
            ActiveDisplayResolver.displayID(for: $0) == displayID
        }?.maximumFramesPerSecond ?? 60)
        try await start(filter: filter, configuration: configuration, maximumFramesPerSecond: maximumFramesPerSecond)
        AppLog.event("capture", "area_capture_stream_started", fields: ["display": String(describing: displayID), "excluded_floating_windows": String(describing: AreaCaptureWindowFilter.excludedWindows(in: content).count), "frame_capacity": String(describing: frames.capacity), "history_ms": "250", "maximum_frame_rate": String(describing: maximumFramesPerSecond), "wallpaper_covers": String(describing: DesktopIconVisibilityService.shared.coverWindowIDs.count)])
    }

    func start(window: SCWindow, includeShadow: Bool, showsCursor: Bool) async throws {
        windowID = window.windowID
        let filter = SCContentFilter(desktopIndependentWindow: window)
        windowScale = CGFloat(filter.pointPixelScale)
        let configuration = SCStreamConfiguration()
        if includeShadow {
            let sizing = try await AreaCaptureWindowSnapshot.capture(window: window, includeShadow: true)
            configuration.width = sizing.image.width
            configuration.height = sizing.image.height
        } else {
            configuration.width = Int(ceil(filter.contentRect.width * windowScale))
            configuration.height = Int(ceil(filter.contentRect.height * windowScale))
        }
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.colorSpaceName = CGColorSpace.sRGB
        configuration.includeChildWindows = false
        configuration.showsCursor = showsCursor
        configuration.ignoreShadowsSingleWindow = !includeShadow
        let maximumFramesPerSecond = max(1, NSScreen.screens.first {
            ActiveDisplayResolver.displayID(for: $0) == displayID
        }?.maximumFramesPerSecond ?? 60)
        try await start(filter: filter, configuration: configuration, maximumFramesPerSecond: maximumFramesPerSecond)
        AppLog.event("capture", "area_window_stream_started", fields: ["frame_capacity": String(describing: frames.capacity), "shadow": String(describing: includeShadow), "window": String(describing: window.windowID)])
    }

    private func start(filter: SCContentFilter, configuration: SCStreamConfiguration, maximumFramesPerSecond: Int) async throws {
        frames = AreaCaptureFrameRing(maximumFramesPerSecond: maximumFramesPerSecond)
        frameBufferPool = try AreaCaptureFrameBufferPool(width: configuration.width, height: configuration.height,
                                                       maximumBufferCount: frames.capacity + 1)
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(maximumFramesPerSecond))
        configuration.queueDepth = 3
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        self.stream = stream
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .main)
        try await stream.startCapture()
    }

    func snapshot(for eventTime: TimeInterval) throws -> AreaCaptureSnapshot {
        guard let selection = frames.selection(for: eventTime) else {
            AppLog.event("capture", "area_capture_frame_unavailable", fields: ["display": String(describing: displayID), "retained_frames": String(describing: frames.count)])
            throw CocoaError(.fileReadUnknown)
        }
        if selection.usedOldestFallback {
            AppLog.event("capture", "area_capture_frame_fallback_used", fields: ["display": String(describing: displayID), "gap_ms": String(format: "%.3f", (selection.frame.presentationTime - eventTime) * 1000), "retained_frames": String(describing: frames.count)])
        }
        acceptingFrames = false
        return AreaCaptureSnapshot(displayID: displayID, frame: frame, image: try Self.image(from: selection.frame.value),
                                   presentationTime: selection.frame.presentationTime)
    }

    func windowSnapshot(for eventTime: TimeInterval) throws -> AreaCaptureWindowSnapshot {
        let snapshot = try snapshot(for: eventTime)
        return AreaCaptureWindowSnapshot(image: snapshot.image, scale: windowScale, presentationTime: snapshot.presentationTime,
                                         requestTime: ProcessInfo.processInfo.systemUptime)
    }

    func magnifierImage(at point: CGPoint, geometry: AreaCaptureSnapshot) -> CGImage? {
        guard let buffer = frames.newest?.value else { return nil }
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
            frames.removeAll()
            frameBufferPool = nil
        }
        if !stoppedBySystem {
            do {
                try await stream.stopCapture()
            } catch {
                AppLog.event("capture", "area_capture_stream_stop_failed", fields: ["display": String(describing: displayID), "error": AppLog.error(error)])
                throw error
            }
        }
        if let windowID { AppLog.event("capture", "area_window_stream_stopped", fields: ["window": String(describing: windowID)]) }
        else { AppLog.event("capture", "area_capture_stream_stopped", fields: ["display": String(describing: displayID)]) }
    }

    static func image(from sample: CMSampleBuffer) throws -> CGImage {
        guard let buffer = CMSampleBufferGetImageBuffer(sample) else { throw CocoaError(.fileReadCorruptFile) }
        return try image(from: buffer)
    }

    static func image(from buffer: CVPixelBuffer) throws -> CGImage {
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
                failed = true
                didFail(CocoaError(.fileReadUnknown))
                return
            }
            guard status == SCFrameStatus.complete.rawValue, let time = Self.presentationTime(of: sampleBuffer) else { return }
            do {
                guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer), let frameBufferPool else { throw CocoaError(.fileReadCorruptFile) }
                frames.receive(try frameBufferPool.copy(buffer), presentedAt: time)
                didUpdate()
            } catch {
                acceptingFrames = false
                failed = true
                AppLog.event("capture", "area_capture_frame_retention_failed", fields: ["display": String(describing: displayID), "error": AppLog.error(error)])
                didFail(error)
            }
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in
            stoppedBySystem = true
            guard acceptingFrames else { return }
            failed = true
            AppLog.event("capture", "area_capture_stream_failed", fields: ["display": String(describing: displayID), "error": AppLog.error(error)])
            didFail(error)
        }
    }
}
