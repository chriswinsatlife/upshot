import AppKit
import AVFoundation
@preconcurrency import CoreMedia
import Observation
import QuartzCore

nonisolated struct CameraRecordingResult: Sendable {

    let firstFrameUptime: TimeInterval
    let pixelWidth: Int
    let pixelHeight: Int
}

nonisolated enum RecordingDeviceCatalog {
    static func cameras() -> [AVCaptureDevice] {
        guard !UpshotStorage.isRenderingStates else { return [] }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
    }

    static func microphones() -> [AVCaptureDevice] {
        guard !UpshotStorage.isRenderingStates else { return [] }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone],
            mediaType: .audio,
            position: .unspecified
        ).devices
    }

    static func camera(withID uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return cameras().first { $0.uniqueID == uniqueID }
    }

    static func microphone(withID uniqueID: String) -> AVCaptureDevice? {
        guard !uniqueID.isEmpty else { return nil }
        return microphones().first { $0.uniqueID == uniqueID }
    }
}

@MainActor
final class CameraRecordingManager {
    static let shared = CameraRecordingManager()

    private let engine = CameraCaptureEngine()
    private var previewPanel: NSPanel?
    private var activePreviewDisplayID: CGDirectDisplayID?
    private(set) var isRunning = false

    private(set) var isWriting = false
    private var activeDeviceID: String?

    private init() {}

    @discardableResult
    func startPreview(deviceID: String, displayID: CGDirectDisplayID?) async -> Bool {
        guard !isWriting else { return true }
        if isRunning {
            if activeDeviceID == deviceID {
                showPreview(displayID: displayID)
                return true
            }
            await stopPreview()
        }
        guard let device = RecordingDeviceCatalog.camera(withID: deviceID) else { return false }

        let authorized = await AVCaptureDevice.requestAccess(for: .video)
        guard authorized else { return false }

        do {
            try await engine.startSession(device: device)
        } catch {
            print("Camera preview failed to start: \(error)")
            return false
        }

        isRunning = true
        activeDeviceID = deviceID
        showPreview(displayID: displayID)
        return true
    }

    func stopPreview() async {
        guard isRunning, !isWriting else { return }
        isRunning = false
        activeDeviceID = nil
        hidePreview()
        await engine.stopSessionOnly()
    }

    func start(outputURL: URL, deviceID: String, displayID: CGDirectDisplayID?) async -> Bool {
        guard !isWriting else { return true }

        if !isRunning || activeDeviceID != deviceID {
            guard await startPreview(deviceID: deviceID, displayID: displayID) else { return false }
        } else {
            showPreview(displayID: displayID)
        }

        do {
            try await engine.beginWriting(outputURL: outputURL)
        } catch {
            print("Camera recording failed to start: \(error)")
            isRunning = false
            activeDeviceID = nil
            hidePreview()
            await engine.stopSessionOnly()
            return false
        }

        isWriting = true
        return true
    }

    func pause() {
        guard isWriting else { return }
        engine.pause()
    }

    func resume() {
        guard isWriting else { return }
        engine.resume()
    }

    func stop() async -> CameraRecordingResult? {
        guard isWriting else { return nil }
        isRunning = false
        isWriting = false
        activeDeviceID = nil
        hidePreview()
        return await engine.finish()
    }

    func cancel() async {
        guard isRunning else { return }
        isRunning = false
        isWriting = false
        activeDeviceID = nil
        hidePreview()
        await engine.cancel()
    }

    private func showPreview(displayID: CGDirectDisplayID?) {

        if previewPanel != nil, activePreviewDisplayID == displayID {
            return
        }
        hidePreview()

        let diameter: CGFloat = 160
        let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let origin = CGPoint(
            x: visibleFrame.maxX - diameter - 24,
            y: visibleFrame.minY + 24
        )

        let panel = NSPanel(
            contentRect: CGRect(origin: origin, size: CGSize(width: diameter, height: diameter)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        PreviewWindowCaptureExclusion.shared.register(window: panel)

        let previewLayer = engine.makePreviewLayer()
        previewLayer.videoGravity = .resizeAspectFill
        let container = Self.previewContent(size: CGSize(width: diameter, height: diameter), layer: previewLayer)

        panel.contentView = container
        panel.orderFrontRegardless()
        previewPanel = panel
        activePreviewDisplayID = displayID
    }

    static func renderPreview(player: AVPlayer) -> NSView {
        precondition(UpshotStorage.isRenderingStates)
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspectFill
        return previewContent(size: CGSize(width: 160, height: 160), layer: layer)
    }

    private static func previewContent(size: CGSize, layer: CALayer) -> NSView {
        let container = NSView(frame: CGRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.cornerRadius = size.width / 2
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        container.layer?.borderWidth = 1
        layer.frame = container.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        container.layer?.addSublayer(layer)
        return container
    }

    private func hidePreview() {
        previewPanel?.orderOut(nil)
        previewPanel = nil
        activePreviewDisplayID = nil
    }
}

nonisolated private final class CameraCaptureEngine: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.upshot.camera.session", qos: .userInitiated)
    private let videoQueue = DispatchQueue(label: "com.upshot.camera.video", qos: .userInitiated)
    private let writer = CameraMovieWriter()
    private var input: AVCaptureDeviceInput?
    private var output: AVCaptureVideoDataOutput?
    private var activeDevice: AVCaptureDevice?

    func startSession(device: AVCaptureDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                do {
                    try configureSession(device: device)
                    activeDevice = device
                    session.startRunning()
                    continuation.resume()
                } catch {
                    teardownSession()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func beginWriting(outputURL: URL) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [self] in
                guard let activeDevice else {
                    continuation.resume(throwing: CocoaError(.fileWriteUnknown))
                    return
                }
                do {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(activeDevice.activeFormat.formatDescription)
                    try writer.setup(
                        outputURL: outputURL,
                        width: Int(dimensions.width),
                        height: Int(dimensions.height)
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    func pause() {
        writer.pause()
    }

    func resume() {
        writer.resume()
    }

    func finish() async -> CameraRecordingResult? {
        await stopSession()
        return await writer.finish()
    }

    func cancel() async {
        await stopSession()
        await writer.cancel()
    }

    func stopSessionOnly() async {
        await stopSession()
    }

    func makePreviewLayer() -> AVCaptureVideoPreviewLayer {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        if let connection = layer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        return layer
    }

    private func configureSession(device: AVCaptureDevice) throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CocoaError(.featureUnsupported)
        }
        session.addInput(input)
        self.input = input

        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else {
            throw CocoaError(.featureUnsupported)
        }
        session.addOutput(output)
        self.output = output

        if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }

    private func stopSession() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async { [self] in
                teardownSession()
                continuation.resume()
            }
        }
    }

    private func teardownSession() {
        if session.isRunning {
            session.stopRunning()
        }
        session.beginConfiguration()
        if let input {
            session.removeInput(input)
        }
        if let output {
            session.removeOutput(output)
        }
        session.commitConfiguration()
        input = nil
        output = nil
        activeDevice = nil
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        writer.writeVideoSample(sampleBuffer)
    }
}

nonisolated private final class CameraMovieWriter: @unchecked Sendable {
    private let writingQueue = DispatchQueue(label: "com.upshot.camera.writer", qos: .userInitiated)
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var isSessionStarted = false
    private var sessionStartTime: CMTime?
    private var isPaused = false
    private var pauseStartTime: CMTime?
    private var totalPauseDuration: CMTime = .zero
    private var needsPauseDurationUpdate = false
    private var latestSampleTime: CMTime?
    private var pixelWidth = 0
    private var pixelHeight = 0

    func setup(outputURL: URL, width: Int, height: Int) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: max(6_000_000, width * height * 6),
                AVVideoExpectedSourceFrameRateKey: 30
            ] as [String: Any]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }

        writingQueue.sync {
            assetWriter = writer
            videoInput = input
            self.outputURL = outputURL
            isSessionStarted = false
            sessionStartTime = nil
            isPaused = false
            pauseStartTime = nil
            totalPauseDuration = .zero
            needsPauseDurationUpdate = false
            latestSampleTime = nil
            pixelWidth = width
            pixelHeight = height
        }
    }

    func pause() {
        writingQueue.async { [weak self] in
            guard let self, !isPaused else { return }
            isPaused = true
            pauseStartTime = latestSampleTime
        }
    }

    func resume() {
        writingQueue.async { [weak self] in
            guard let self, isPaused else { return }
            isPaused = false
            needsPauseDurationUpdate = true
        }
    }

    func writeVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let sendable = SendableCameraSampleBuffer(sampleBuffer)

        writingQueue.sync { [weak self] in
            autoreleasepool {
                guard let self,
                      let assetWriter = self.assetWriter,
                      let videoInput = self.videoInput else {
                    return
                }

                let sampleBuffer = sendable.sampleBuffer
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                if self.isPaused {
                    if self.pauseStartTime == nil {
                        self.pauseStartTime = time
                    }
                    return
                }

                if self.needsPauseDurationUpdate {
                    if let pauseStartTime = self.pauseStartTime {
                        self.totalPauseDuration = CMTimeAdd(
                            self.totalPauseDuration,
                            CMTimeSubtract(time, pauseStartTime)
                        )
                        self.pauseStartTime = nil
                    }
                    self.needsPauseDurationUpdate = false
                }

                if !self.isSessionStarted {
                    self.sessionStartTime = time
                    assetWriter.startSession(atSourceTime: .zero)
                    self.isSessionStarted = true
                }

                self.latestSampleTime = time

                var adjusted = time
                if let sessionStartTime = self.sessionStartTime {
                    adjusted = CMTimeSubtract(adjusted, sessionStartTime)
                }
                if self.totalPauseDuration > .zero {
                    adjusted = CMTimeSubtract(adjusted, self.totalPauseDuration)
                }
                guard adjusted >= .zero,
                      videoInput.isReadyForMoreMediaData,
                      assetWriter.status == .writing,
                      let retimed = Self.retime(sampleBuffer, to: adjusted) else {
                    return
                }
                videoInput.append(retimed)
            }
        }
    }

    func finish() async -> CameraRecordingResult? {
        await withCheckedContinuation { continuation in
            writingQueue.async { [weak self] in
                guard let self, let assetWriter = self.assetWriter else {
                    continuation.resume(returning: nil)
                    return
                }

                let result: CameraRecordingResult? = self.sessionStartTime.map {
                    CameraRecordingResult(
                        firstFrameUptime: $0.seconds,
                        pixelWidth: self.pixelWidth,
                        pixelHeight: self.pixelHeight
                    )
                }

                self.videoInput?.markAsFinished()
                assetWriter.finishWriting {
                    let succeeded = assetWriter.status == .completed
                    if !succeeded, let outputURL = self.outputURL {
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                    self.reset()
                    continuation.resume(returning: succeeded ? result : nil)
                }
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                assetWriter?.cancelWriting()
                if let outputURL {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                reset()
                continuation.resume()
            }
        }
    }

    private func reset() {
        assetWriter = nil
        videoInput = nil
        outputURL = nil
        isSessionStarted = false
        sessionStartTime = nil
        isPaused = false
        pauseStartTime = nil
        totalPauseDuration = .zero
        needsPauseDurationUpdate = false
        latestSampleTime = nil
    }

    private static func retime(_ sampleBuffer: CMSampleBuffer, to newPTS: CMTime) -> CMSampleBuffer? {
        var timing = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &newBuffer
        )
        return status == noErr ? newBuffer : nil
    }
}

nonisolated private struct SendableCameraSampleBuffer: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(_ sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}
