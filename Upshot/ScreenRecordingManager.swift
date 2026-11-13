import AppKit
import AVFoundation
@preconcurrency import CoreMedia
import Observation
import ScreenCaptureKit

enum ScreenRecordingState: Equatable {
    case idle
    case starting
    case recording
    case paused
    case finishing
}

enum ScreenRecordingSourceMode: String, CaseIterable, Identifiable {
    case fullscreen
    case window
    case area

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fullscreen:
            "Full Screen"
        case .window:
            "Window"
        case .area:
            "Area"
        }
    }

    var systemImage: String {
        switch self {
        case .fullscreen:
            "display"
        case .window:
            "macwindow"
        case .area:
            "rectangle.dashed"
        }
    }
}

struct ScreenRecordingSource {
    enum Kind {
        case fullscreen(SCDisplay)
        case window(SCWindow)
        case area(display: SCDisplay, rect: CGRect)
    }

    let kind: Kind

    var captureSource: CaptureSource? {
        switch kind {
        case .window(let window):
            guard let app = window.owningApplication else { return nil }
            let title = window.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return CaptureSource(
                bundleIdentifier: app.bundleIdentifier.isEmpty ? nil : app.bundleIdentifier,
                appName: app.applicationName,
                windowTitle: title?.isEmpty == false ? title : nil
            )
        case .fullscreen(let display), .area(let display, _):
            return CaptureSourceProbe(tracksPointer: false).finish(.display(display.displayID))
        }
    }

    var displayID: CGDirectDisplayID? {
        switch kind {
        case .fullscreen(let display):
            display.displayID
        case .window:
            nil
        case .area(let display, _):
            display.displayID
        }
    }
}

private enum ScreenRecordingFinishAction: Equatable {
    case preview
    case discard
    case restart
    case terminate
}

nonisolated struct ScreenRecordingCaptureOptions: Sendable {
    var capturesSystemAudio = false
    var microphoneDeviceID: String?
    var cameraDeviceID: String?

    @MainActor
    static func fromPreferences() -> ScreenRecordingCaptureOptions {
        var options = ScreenRecordingCaptureOptions()
        options.capturesSystemAudio = UpshotPreferences.recordingSystemAudio
        let micID = UpshotPreferences.recordingMicrophoneDeviceID
        options.microphoneDeviceID = micID.isEmpty ? nil : micID
        let cameraID = UpshotPreferences.recordingCameraDeviceID
        options.cameraDeviceID = cameraID.isEmpty ? nil : cameraID
        return options
    }
}

@MainActor
@Observable
final class ScreenRecordingManager {
    static let shared = ScreenRecordingManager()

    var state: ScreenRecordingState = .idle
    var elapsedTime: TimeInterval = 0
    var errorMessage: String?
    var onFinishRecording: ((RecordingSession, CGDirectDisplayID?) -> Void)?

    private let capture = ScreenRecordingCapture()
    private let writer = ScreenRecordingWriter()
    private let pointerActivityRecorder = PointerActivityRecorder()
    private let keystrokeRecorder = RecordingKeystrokeRecorder()
    private var displayID: CGDirectDisplayID?
    private var session: RecordingSession?
    var activeSessionDirectoryURL: URL? { isActive ? session?.directoryURL : nil }
    private var manifest = CaptureManifest()
    private var startedAt: Date?
    private var pausedAt: Date?
    private var accumulatedPauseDuration: TimeInterval = 0
    private var timer: Timer?
    private var finishAction: ScreenRecordingFinishAction = .preview
    private var isStopping = false
    private var currentSource: ScreenRecordingSource?
    private var activityToken: NSObjectProtocol?
    private var terminationCompletion: ((RecordingSession?) -> Void)?

    var isActive: Bool {
        state != .idle
    }

    var formattedElapsedTime: String {
        let totalSeconds = max(0, Int(elapsedTime.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var menuBarTimerText: String? {
        switch state {
        case .recording, .paused:
            formattedElapsedTime
        case .idle, .starting, .finishing:
            nil
        }
    }

    private init() {}

    func startRecording(source: ScreenRecordingSource) {
        guard state == .idle else { return }
        guard Self.ensureScreenCapturePermission() else { return }

        let targetDisplayID = source.displayID ?? ActiveDisplayResolver.activeDisplayID(preferPointer: true) ?? CGMainDisplayID()
        state = .starting
        elapsedTime = 0
        errorMessage = nil
        displayID = targetDisplayID
        currentSource = source
        finishAction = .preview
        isStopping = false

        CaptureShelfPresenter.shared.setTargetDisplay(targetDisplayID)
        RecordingControlPresenter.shared.show(displayID: targetDisplayID)
        RecordingAreaHighlightPresenter.shared.show(source: source)
        RecordingPenPresenter.shared.prepare(source: source)
        RecordingPenPresenter.shared.onChange = { [writer] in writer.refreshPenFrame() }

        Task {
            do {
                let requestedOptions = ScreenRecordingCaptureOptions.fromPreferences()
                let (options, inputWarnings) = await Self.resolveCaptureOptions(requestedOptions)
                guard state == .starting, !isStopping else { return }

                if !inputWarnings.isEmpty {
                    Self.presentInputWarnings(inputWarnings)
                }

                TeleprompterController.shared.beginRecordingSession(
                    displayID: targetDisplayID,
                    microphoneActive: options.microphoneDeviceID != nil
                )

                let session = try RecordingSessionStore.createSession()
                self.session = session
                let focusWarning = await RecordingFocusController.shared.begin()
                guard isStarting(session: session) else { return }
                if let focusWarning { Self.presentInputWarnings([focusWarning]) }
                let content = try await ScreenRecordingCapture.availableContent()
                guard isStarting(session: session) else { return }
                let target = try Self.captureTarget(for: source, content: content, options: options)

                try writer.setupWriter(
                    outputURL: session.screenURL,
                    videoWidth: target.width,
                    videoHeight: target.height,
                    mapsPenToWindowContent: target.tracksDynamicGeometry,
                    includesSystemAudio: options.capturesSystemAudio,
                    includesMicrophone: options.microphoneDeviceID != nil
                )

                capture.onVideoFrame = { [writer, pointerActivityRecorder] sampleBuffer in
                    pointerActivityRecorder.recordFrameGeometry(sampleBuffer)
                    writer.writeVideoSample(sampleBuffer)
                }
                let teleprompterEngine = TeleprompterController.shared.activeEngine
                capture.onAudioSample = { [writer] sampleBuffer, kind in
                    if kind == .microphone {
                        teleprompterEngine?.ingest(sampleBuffer)
                    }
                    writer.writeAudioSample(sampleBuffer, kind: kind)
                }
                capture.onError = { [weak self] error in
                    Task { @MainActor in
                        self?.handleCaptureError(error)
                    }
                }
                writer.onFailure = { [weak self] error in
                    Task { @MainActor in
                        self?.handleWriterFailure(error)
                    }
                }

                var cameraStarted = false
                if let cameraID = options.cameraDeviceID {
                    cameraStarted = await CameraRecordingManager.shared.start(
                        outputURL: session.cameraURL,
                        deviceID: cameraID,
                        displayID: targetDisplayID
                    )
                    guard isStarting(session: session) else { return }
                    if !cameraStarted {
                        Self.presentInputWarnings([
                            "The selected camera could not start. The screen and selected audio will still be recorded."
                        ])
                    }
                }

                pointerActivityRecorder.start(
                    mapping: target.inputMapping,
                    tracksDynamicGeometry: target.tracksDynamicGeometry
                )
                keystrokeRecorder.start()

                try await capture.startCapture(filter: target.filter, configuration: target.configuration)
                guard isStarting(session: session) else { return }

                manifest = CaptureManifest()
                manifest.pixelWidth = target.width
                manifest.pixelHeight = target.height
                manifest.pixelScale = target.pointPixelScale
                manifest.sourceDisplayID = target.displayID
                manifest.pointerSynthesized = true
                manifest.pressEffectsBaked = false
                manifest.pressEffectsEnabled = true
                manifest.includesSystemAudio = options.capturesSystemAudio
                manifest.includesMicrophone = options.microphoneDeviceID != nil
                manifest.source = source.captureSource
                if !cameraStarted {
                    manifest.cameraLeadIn = nil
                }

                startedAt = Date()
                pausedAt = nil
                accumulatedPauseDuration = 0
                elapsedTime = 0
                state = .recording
                NSLog("[Upshot] Recording timer started")
                beginActivity()
                startTimer()
            } catch {
                await finishFailedStart(error: error)
            }
        }
    }

    func stopRecording() {
        guard state == .recording || state == .paused else { return }
        finishAction = .preview
        stopCaptureAndFinish()
    }

    func pauseRecording() {
        guard state == .recording else { return }

        RecordingPenPresenter.shared.setPaused(true)
        writer.pause()
        pointerActivityRecorder.pause()
        keystrokeRecorder.pause()
        CameraRecordingManager.shared.pause()
        TeleprompterController.shared.setPaused(true)
        pausedAt = Date()
        state = .paused
        NSLog("[Upshot] Recording timer paused at \(formattedElapsedTime)")
        updateElapsedTime()
    }

    func resumeRecording() {
        guard state == .paused else { return }

        if let pausedAt {
            accumulatedPauseDuration += Date().timeIntervalSince(pausedAt)
        }

        self.pausedAt = nil
        RecordingPenPresenter.shared.setPaused(false)
        writer.resume()
        pointerActivityRecorder.resume()
        keystrokeRecorder.resume()
        CameraRecordingManager.shared.resume()
        TeleprompterController.shared.setPaused(false)
        state = .recording
        updateElapsedTime()
        NSLog("[Upshot] Recording timer resumed at \(formattedElapsedTime)")
    }

    func restartRecording() {
        guard state == .recording || state == .paused else { return }
        finishAction = .restart
        stopCaptureAndFinish()
    }

    func deleteRecording() {
        guard state != .idle else {
            RecordingControlPresenter.shared.hide()
            RecordingAreaHighlightPresenter.shared.hide()
            return
        }

        finishAction = .discard
        stopCaptureAndFinish()
    }

    func finishForTermination(completion: @escaping (RecordingSession?) -> Void) {
        guard state != .idle else {
            completion(nil)
            return
        }

        terminationCompletion = completion
        finishAction = .terminate
        stopCaptureAndFinish()
    }

    private func stopCaptureAndFinish() {
        guard !isStopping else { return }

        isStopping = true
        state = .finishing
        RecordingPenPresenter.shared.setPaused(true)
        timer?.invalidate()
        pointerActivityRecorder.stop()
        keystrokeRecorder.stop()

        Task {
            do {
                try await capture.stopCapture()
            } catch {
                print("Screen recording capture stop failed: \(error)")
            }
            RecordingAreaHighlightPresenter.shared.hide()

            let cameraResult = await CameraRecordingManager.shared.stop()
            let result = await writer.finishWriting()
            RecordingPenPresenter.shared.finish()
            if let warning = await RecordingFocusController.shared.restore() {
                errorMessage = [errorMessage, warning].compactMap { $0 }.joined(separator: "\n\n")
            }
            finalizeSession(result: result, cameraResult: cameraResult)
        }
    }

    private func finalizeSession(result: ScreenRecordingWriterResult, cameraResult: CameraRecordingResult?) {
        let action = finishAction
        let restartSource = currentSource
        let restartDisplayID = displayID
        let session = session
        let terminationCompletion = terminationCompletion
        var metadataWarnings: [String] = []

        if let session, result.fileIsUsable {
            manifest.duration = result.duration
            if let cameraResult, let sessionStart = result.sessionStartUptime {
                manifest.cameraLeadIn = cameraResult.firstFrameUptime - sessionStart
                manifest.cameraWidth = cameraResult.pixelWidth
                manifest.cameraHeight = cameraResult.pixelHeight
            }
            if let sessionStart = result.sessionStartUptime {
                var capture = pointerActivityRecorder.finish(sessionStartUptime: sessionStart, duration: result.duration)
                capture.keystrokes = keystrokeRecorder.finish(
                    sessionStartUptime: sessionStart,
                    duration: result.duration
                )
                do {
                    try session.writePointerCapture(capture)
                } catch {
                    NSLog("[Upshot] Failed to save recording input timeline: \(error)")
                    metadataWarnings.append(
                        "The screen footage was saved, but its cursor and click data could not be saved."
                    )
                }
            } else {
                metadataWarnings.append(
                    "The screen footage was saved, but its cursor timeline could not be aligned to the video."
                )
            }
            do {
                try session.writeCaptureManifest(manifest)
            } catch {
                NSLog("[Upshot] Failed to save recording manifest: \(error)")
                metadataWarnings.append(
                    "The screen footage was saved, but some Studio metadata could not be saved."
                )
            }
        }

        cleanupAfterRecording()

        guard let session, result.fileIsUsable else {
            if let session {
                RecordingSessionStore.deleteSession(session)
            }
            errorMessage = result.error.map { "Recording failed: \($0.localizedDescription)" }
                ?? "Failed to finish recording."
            RecordingControlPresenter.shared.hide()
            RecordingAreaHighlightPresenter.shared.hide()
            if action == .terminate {
                terminationCompletion?(nil)
            } else if let errorMessage {
                Self.presentRecordingResultAlert(message: errorMessage, footageWasSaved: false)
            }
            return
        }

        if !metadataWarnings.isEmpty {
            let warning = metadataWarnings.joined(separator: "\n\n")
            errorMessage = [errorMessage, warning]
                .compactMap { $0 }
                .joined(separator: "\n\n")
        }

        if let error = result.error {
            let warning = "Recording ended early (\(error.localizedDescription)). Everything captured so far was saved."
            errorMessage = [errorMessage, warning]
                .compactMap { $0 }
                .joined(separator: "\n\n")
        }

        switch action {
        case .preview:
            RecordingControlPresenter.shared.hide()
            RecordingAreaHighlightPresenter.shared.hide()
            if let errorMessage {
                Self.presentRecordingResultAlert(message: errorMessage, footageWasSaved: true)
            }
            onFinishRecording?(session, restartDisplayID)
        case .discard:
            RecordingSessionStore.deleteSession(session)
            RecordingControlPresenter.shared.hide()
            RecordingAreaHighlightPresenter.shared.hide()
        case .restart:
            RecordingSessionStore.deleteSession(session)
            if let restartSource {
                startRecording(source: restartSource)
            }
        case .terminate:
            RecordingControlPresenter.shared.hide()
            RecordingAreaHighlightPresenter.shared.hide()
            terminationCompletion?(session)
        }
    }

    private func handleCaptureError(_ error: Error) {
        guard state == .recording || state == .paused || state == .starting else { return }

        if state == .starting {
            errorMessage = "Screen recording failed to start: \(error.localizedDescription)"
            finishAction = .discard
        } else {
            errorMessage = "Recording stopped (\(error.localizedDescription)). Everything captured so far was saved."
            finishAction = .preview
        }
        stopCaptureAndFinish()
    }

    private func handleWriterFailure(_ error: Error) {
        guard state == .recording || state == .paused else { return }

        errorMessage = "Recording stopped (\(error.localizedDescription)). Everything captured so far was saved."
        finishAction = .preview
        terminationCompletion = nil
        stopCaptureAndFinish()
    }

    private func finishFailedStart(error: Error) async {
        guard !isStopping else { return }
        isStopping = true
        try? await capture.stopCapture()
        await writer.cancel()
        await CameraRecordingManager.shared.cancel()
        pointerActivityRecorder.stop()
        RecordingAreaHighlightPresenter.shared.hide()
        RecordingPenPresenter.shared.finish()
        if let session {
            RecordingSessionStore.deleteSession(session)
        }
        let focusWarning = await RecordingFocusController.shared.restore()
        cleanupAfterRecording()
        errorMessage = "Failed to start screen recording: \(error.localizedDescription)"
        RecordingControlPresenter.shared.hide()
        RecordingAreaHighlightPresenter.shared.hide()
        if let focusWarning { Self.presentInputWarnings([focusWarning]) }
        Self.presentStartFailureAlert(error: error)
    }

    private func isStarting(session: RecordingSession) -> Bool {
        state == .starting && !isStopping && self.session == session
    }

    private static func resolveCaptureOptions(
        _ requested: ScreenRecordingCaptureOptions
    ) async -> (ScreenRecordingCaptureOptions, [String]) {
        var resolved = requested
        var warnings: [String] = []

        if let microphoneID = requested.microphoneDeviceID {
            if RecordingDeviceCatalog.microphone(withID: microphoneID) == nil {
                resolved.microphoneDeviceID = nil
                UpshotPreferences.recordingMicrophoneDeviceID = ""
                warnings.append("The selected microphone is no longer available, so it was turned off.")
            } else if !(await RecordingInputAuthorization.requestAccess(for: .microphone)) {
                resolved.microphoneDeviceID = nil
                UpshotPreferences.recordingMicrophoneDeviceID = ""
                warnings.append("Microphone access is not allowed, so this recording will not include narration.")
            }
        }

        if let cameraID = requested.cameraDeviceID {
            if RecordingDeviceCatalog.camera(withID: cameraID) == nil {
                resolved.cameraDeviceID = nil
                UpshotPreferences.recordingCameraDeviceID = ""
                warnings.append("The selected camera is no longer available, so it was turned off.")
            } else if !(await RecordingInputAuthorization.requestAccess(for: .camera)) {
                resolved.cameraDeviceID = nil
                UpshotPreferences.recordingCameraDeviceID = ""
                warnings.append("Camera access is not allowed, so this recording will not include a camera bubble.")
            }
        }

        return (resolved, warnings)
    }

    private static func presentInputWarnings(_ warnings: [String]) {
        guard !warnings.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Some recording inputs are unavailable"
        alert.informativeText = warnings.joined(separator: "\n\n")
        alert.addButton(withTitle: "Continue")
        alert.runModal()
    }

    private static func presentRecordingResultAlert(message: String, footageWasSaved: Bool) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = footageWasSaved ? .informational : .critical
        alert.messageText = footageWasSaved
            ? "The recording ended early, but your footage was saved"
            : "The recording could not be saved"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private static func ensureScreenCapturePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }
        if CGRequestScreenCaptureAccess() {
            return true
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
        Upshot can't record until it's allowed under Privacy & Security > \
        Screen & System Audio Recording. After turning it on, quit and reopen \
        Upshot - macOS applies the permission on relaunch.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
        return false
    }

    private static func presentStartFailureAlert(error: Error) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Couldn't start the recording"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func beginActivity() {
        endActivity()
        activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Screen recording in progress"
        )
    }

    private func endActivity() {
        if let activityToken {
            ProcessInfo.processInfo.endActivity(activityToken)
        }
        activityToken = nil
    }

    private func startTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { _ in
            Task { @MainActor in
                ScreenRecordingManager.shared.updateElapsedTime()
                guard RecordingAreaHighlightPresenter.shared.update() else {
                    ScreenRecordingManager.shared.handleCaptureError(NSError(
                        domain: "UpshotRecording",
                        code: 1,
                        userInfo: [NSLocalizedDescriptionKey: "The display configuration changed."]
                    ))
                    return
                }
                RecordingPenPresenter.shared.updateGeometry()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func updateElapsedTime() {
        guard let startedAt else {
            elapsedTime = 0
            return
        }

        let pauseDuration: TimeInterval
        if state == .paused, let pausedAt {
            pauseDuration = accumulatedPauseDuration + Date().timeIntervalSince(pausedAt)
        } else {
            pauseDuration = accumulatedPauseDuration
        }

        elapsedTime = max(0, Date().timeIntervalSince(startedAt) - pauseDuration)
    }

    private func cleanupAfterRecording() {
        RecordingPenPresenter.shared.finish()
        RecordingAreaHighlightPresenter.shared.hide()
        timer?.invalidate()
        timer = nil
        capture.onVideoFrame = nil
        capture.onAudioSample = nil
        capture.onError = nil
        writer.onFailure = nil
        pointerActivityRecorder.stop()
        keystrokeRecorder.stop()
        TeleprompterController.shared.endRecordingSession()
        endActivity()
        session = nil
        displayID = nil
        currentSource = nil
        startedAt = nil
        pausedAt = nil
        accumulatedPauseDuration = 0
        finishAction = .preview
        isStopping = false
        state = .idle
        NSLog("[Upshot] Recording timer cleared")
    }

    private static func captureTarget(
        for source: ScreenRecordingSource,
        content: SCShareableContent,
        options: ScreenRecordingCaptureOptions
    ) throws -> ScreenRecordingCaptureTarget {
        let filter: SCContentFilter
        let sourceSize: CGSize
        var sourceRect: CGRect?
        let captureRect: CGRect
        let displayID: CGDirectDisplayID?
        let tracksDynamicGeometry: Bool
        let includesAppWindows = PreviewWindowCaptureExclusion.includesAppWindowsInCaptures

        switch source.kind {
        case .fullscreen(let display):
            let freshDisplay = content.displays.first(where: { $0.displayID == display.displayID }) ?? display
            filter = ScreenRecordingCapture.displayFilter(
                display: freshDisplay,
                content: content,
                includesAppWindows: includesAppWindows
            )
            sourceSize = CGSize(width: freshDisplay.width, height: freshDisplay.height)
            let bounds = CGDisplayBounds(freshDisplay.displayID)
            captureRect = bounds.isEmpty ? freshDisplay.frame : bounds
            displayID = freshDisplay.displayID
            tracksDynamicGeometry = false
        case .window(let window):
            let freshWindow = content.windows.first(where: { $0.windowID == window.windowID }) ?? window
            filter = SCContentFilter(desktopIndependentWindow: freshWindow)
            sourceSize = freshWindow.frame.size
            captureRect = freshWindow.frame
            displayID = nil
            tracksDynamicGeometry = true
        case .area(let display, let rect):
            let freshDisplay = content.displays.first(where: { $0.displayID == display.displayID }) ?? display
            filter = ScreenRecordingCapture.displayFilter(
                display: freshDisplay,
                content: content,
                includesAppWindows: includesAppWindows
            )
            let mappedSourceRect = Self.sourceRect(
                forAppKitSelectionRect: rect,
                screenFrame: ActiveDisplayResolver.screen(for: freshDisplay.displayID)?.frame,
                contentRect: filter.contentRect
            )
            sourceRect = mappedSourceRect
            sourceSize = mappedSourceRect.size
            captureRect = Self.quartzRect(fromAppKitRect: rect)
            displayID = freshDisplay.displayID
            tracksDynamicGeometry = false
        }

        let scaleFactor = max(1, CGFloat(filter.pointPixelScale))
        let width = max(2, Int((sourceSize.width * scaleFactor).rounded(.toNearestOrAwayFromZero)))
        let height = max(2, Int((sourceSize.height * scaleFactor).rounded(.toNearestOrAwayFromZero)))
        let configuration = ScreenRecordingCapture.buildConfiguration(
            width: width,
            height: height,
            sourceRect: sourceRect,
            options: options
        )
        let inputMapping = RecordingInputMapping(
            captureRect: captureRect,
            pixelWidth: width,
            pixelHeight: height
        )
        return ScreenRecordingCaptureTarget(
            filter: filter,
            configuration: configuration,
            width: width,
            height: height,
            displayID: displayID,
            pointPixelScale: Double(scaleFactor),
            tracksDynamicGeometry: tracksDynamicGeometry,
            inputMapping: inputMapping
        )
    }

    private static func quartzRect(fromAppKitRect rect: CGRect) -> CGRect {
        let mainDisplayHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: rect.minX,
            y: mainDisplayHeight - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    private static func sourceRect(
        forAppKitSelectionRect selectionRect: CGRect,
        screenFrame: CGRect?,
        contentRect: CGRect
    ) -> CGRect {
        guard let screenFrame,
              screenFrame.width > 0,
              screenFrame.height > 0,
              contentRect.width > 0,
              contentRect.height > 0 else {
            return clamped(selectionRect, to: contentRect)
        }

        let minLocalX = min(max(selectionRect.minX - screenFrame.minX, 0), screenFrame.width)
        let maxLocalX = min(max(selectionRect.maxX - screenFrame.minX, 0), screenFrame.width)
        let minLocalY = min(max(selectionRect.minY - screenFrame.minY, 0), screenFrame.height)
        let maxLocalY = min(max(selectionRect.maxY - screenFrame.minY, 0), screenFrame.height)

        let scaleX = contentRect.width / screenFrame.width
        let scaleY = contentRect.height / screenFrame.height
        let sourceX = contentRect.minX + minLocalX * scaleX
        let sourceY = contentRect.minY + (screenFrame.height - maxLocalY) * scaleY
        let sourceWidth = max(1, (maxLocalX - minLocalX) * scaleX)
        let sourceHeight = max(1, (maxLocalY - minLocalY) * scaleY)

        return clamped(
            CGRect(x: sourceX, y: sourceY, width: sourceWidth, height: sourceHeight),
            to: contentRect
        )
    }

    private static func clamped(_ rect: CGRect, to bounds: CGRect) -> CGRect {
        guard bounds.width > 0, bounds.height > 0 else {
            return .zero
        }

        let width = min(max(rect.width, 1), bounds.width)
        let height = min(max(rect.height, 1), bounds.height)
        let minX = min(max(rect.minX, bounds.minX), bounds.maxX - width)
        let minY = min(max(rect.minY, bounds.minY), bounds.maxY - height)
        let maxX = minX + width
        let maxY = minY + height

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

private struct ScreenRecordingCaptureTarget {
    let filter: SCContentFilter
    let configuration: SCStreamConfiguration
    let width: Int
    let height: Int
    let displayID: CGDirectDisplayID?
    let pointPixelScale: Double
    let tracksDynamicGeometry: Bool
    let inputMapping: RecordingInputMapping
}

nonisolated enum ScreenRecordingAudioKind: Sendable {
    case system
    case microphone
}

nonisolated final class ScreenRecordingCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var streamHasAudio = false
    private var streamHasMicrophone = false
    private let videoQueue = DispatchQueue(label: "com.upshot.screen-recording.video", qos: .userInteractive)
    private let audioQueue = DispatchQueue(label: "com.upshot.screen-recording.audio", qos: .userInteractive)

    var onVideoFrame: ((CMSampleBuffer) -> Void)?
    var onAudioSample: ((CMSampleBuffer, ScreenRecordingAudioKind) -> Void)?
    var onError: ((Error) -> Void)?

    static func availableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    func startCapture(filter: SCContentFilter, configuration: SCStreamConfiguration) async throws {
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoQueue)
        streamHasAudio = configuration.capturesAudio
        streamHasMicrophone = configuration.captureMicrophone
        if streamHasAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        }
        if streamHasMicrophone {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: audioQueue)
        }
        try await stream.startCapture()
        self.stream = stream
    }

    func stopCapture() async throws {
        guard let stream else { return }
        self.stream = nil
        defer {
            try? stream.removeStreamOutput(self, type: .screen)
            if streamHasAudio {
                try? stream.removeStreamOutput(self, type: .audio)
            }
            if streamHasMicrophone {
                try? stream.removeStreamOutput(self, type: .microphone)
            }
        }
        try await stream.stopCapture()
    }

    @MainActor static func displayFilter(
        display: SCDisplay,
        content: SCShareableContent,
        includesAppWindows: Bool
    ) -> SCContentFilter {
        let excludedApps = includesAppWindows
            ? []
            : content.applications.filter { application in
                application.bundleIdentifier == Bundle.main.bundleIdentifier
            }

        if includesAppWindows {
            let excludedWindowIDs = RecordingAreaHighlightPresenter.shared.windowIDs.union(RecordingPenPresenter.shared.windowIDs)
            return SCContentFilter(
                display: display,
                excludingWindows: content.windows.filter { excludedWindowIDs.contains($0.windowID) }
            )
        }
        return SCContentFilter(
            display: display,
            excludingApplications: excludedApps,
            exceptingWindows: []
        )
    }

    static func buildConfiguration(
        width: Int,
        height: Int,
        sourceRect: CGRect?,
        options: ScreenRecordingCaptureOptions
    ) -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        if let sourceRect {
            configuration.sourceRect = sourceRect
        }
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.queueDepth = 3
        configuration.showsCursor = false
        configuration.showMouseClicks = false
        configuration.capturesAudio = options.capturesSystemAudio
        if options.capturesSystemAudio {
            configuration.excludesCurrentProcessAudio = true
        }
        configuration.captureMicrophone = options.microphoneDeviceID != nil
        if let microphoneDeviceID = options.microphoneDeviceID {
            configuration.microphoneCaptureDeviceID = microphoneDeviceID
        }
        return configuration
    }

    nonisolated func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard CMSampleBufferDataIsReady(sampleBuffer) else { return }

        switch type {
        case .screen:
            if let status = Self.frameStatus(for: sampleBuffer),
               status == .blank || status == .suspended || status == .stopped {
                return
            }
            onVideoFrame?(sampleBuffer)
        case .audio:
            onAudioSample?(sampleBuffer, .system)
        case .microphone:
            onAudioSample?(sampleBuffer, .microphone)
        @unknown default:
            break
        }
    }

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }

    private static func frameStatus(for sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
              let rawValue = attachments.first?[SCStreamFrameInfo.status] as? Int else {
            return nil
        }

        return SCFrameStatus(rawValue: rawValue)
    }
}

nonisolated struct ScreenRecordingWriterResult: Sendable {
    let url: URL?
    let error: Error?
    let sessionStartUptime: TimeInterval?
    let duration: TimeInterval

    var fileIsUsable: Bool {
        url != nil && sessionStartUptime != nil && duration > 0.1
    }
}

nonisolated private final class ScreenRecordingWriter: @unchecked Sendable {
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private let writingQueue = DispatchQueue(label: "com.upshot.screen-recording.writer", qos: .userInitiated)
    private var outputURL: URL?
    private var isSessionStarted = false
    private var sessionStartTime: CMTime?
    private var isPaused = false
    private var pauseStartTime: CMTime?
    private var totalPauseDuration: CMTime = .zero
    private var latestAdjustedTime: CMTime = .zero
    private var failureError: Error?
    private var didReportFailure = false
    private var latestScreenSample: SendableSampleBuffer?
    private var hasWrittenPen = false
    private var mapsPenToWindowContent = false

    var onFailure: ((Error) -> Void)?

    func setupWriter(
        outputURL: URL,
        videoWidth: Int,
        videoHeight: Int,
        mapsPenToWindowContent: Bool,
        includesSystemAudio: Bool,
        includesMicrophone: Bool
    ) throws {
        try? FileManager.default.removeItem(at: outputURL)

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        writer.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)

        let bitRate = max(20_000_000, videoWidth * videoHeight * 4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitRate,
                AVVideoExpectedSourceFrameRateKey: 60,
                AVVideoMaxKeyFrameIntervalKey: 60
            ] as [String: Any]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true
        writer.add(input)

        var systemAudioInput: AVAssetWriterInput?
        if includesSystemAudio {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 2))
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)
            systemAudioInput = audioInput
        }

        var microphoneInput: AVAssetWriterInput?
        if includesMicrophone {
            let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings(channels: 1))
            audioInput.expectsMediaDataInRealTime = true
            writer.add(audioInput)
            microphoneInput = audioInput
        }

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: videoWidth,
                kCVPixelBufferHeightKey as String: videoHeight
            ]
        )

        guard writer.startWriting() else {
            throw writer.error ?? CocoaError(.fileWriteUnknown)
        }

        writingQueue.sync {
            assetWriter = writer
            videoInput = input
            self.systemAudioInput = systemAudioInput
            self.microphoneInput = microphoneInput
            pixelBufferAdaptor = adaptor
            self.outputURL = outputURL
            self.mapsPenToWindowContent = mapsPenToWindowContent
            isSessionStarted = false
            sessionStartTime = nil
            isPaused = false
            pauseStartTime = nil
            totalPauseDuration = .zero
            latestAdjustedTime = .zero
            failureError = nil
            didReportFailure = false
        }
    }

    private static func audioSettings(channels: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: channels > 1 ? 192_000 : 96_000
        ]
    }

    func pause() {
        let requestedTime = CMClockGetTime(CMClockGetHostTimeClock())
        writingQueue.async { [weak self] in
            guard let self, !isPaused else { return }

            isPaused = true
            pauseStartTime = requestedTime
        }
    }

    func resume() {
        let requestedTime = CMClockGetTime(CMClockGetHostTimeClock())
        writingQueue.async { [weak self] in
            guard let self, isPaused else { return }

            isPaused = false
            if let pauseStartTime {
                totalPauseDuration = CMTimeAdd(totalPauseDuration, CMTimeSubtract(requestedTime, pauseStartTime))
            }
            pauseStartTime = nil
        }
    }

    func refreshPenFrame() {
        let latest = writingQueue.sync { latestScreenSample }
        guard let latest else { return }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()),
            decodeTimeStamp: .invalid
        )
        var refreshed: CMSampleBuffer?
        guard CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: latest.sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleBufferOut: &refreshed
        ) == noErr, let refreshed else { return }
        writeVideoSample(refreshed)
    }

    func writeVideoSample(_ sampleBuffer: CMSampleBuffer) {
        let sendableSampleBuffer = SendableSampleBuffer(sampleBuffer)
        writingQueue.sync { [weak self, sendableSampleBuffer] in
            autoreleasepool {
                guard let self = self,
                      let videoInput = self.videoInput,
                      let pixelBufferAdaptor = self.pixelBufferAdaptor else {
                    return
                }

                let sampleBuffer = sendableSampleBuffer.sampleBuffer
                guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
                self.latestScreenSample = sendableSampleBuffer
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

                if !self.isSessionStarted {
                    self.sessionStartTime = time
                    self.assetWriter?.startSession(atSourceTime: .zero)
                    self.isSessionStarted = true
                }

                guard !self.isPaused else { return }

                let adjustedPTS = self.adjustedTime(time)
                guard adjustedPTS >= .zero, adjustedPTS > self.latestAdjustedTime || self.latestAdjustedTime == .zero, self.checkWriterHealth() else { return }
                guard videoInput.isReadyForMoreMediaData else { return }

                let strokes = RecordingPenStrokeStore.shared.snapshot
                let composited: CVPixelBuffer
                do {
                    let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]]
                    let frame = attachments?.first
                    let contentRect = (frame?[.contentRect] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
                    let scale = (frame?[.scaleFactor] as? NSNumber)?.doubleValue ?? 1
                    let pixelContentRect = contentRect.map {
                        CGRect(x: $0.minX * scale, y: $0.minY * scale, width: $0.width * scale, height: $0.height * scale)
                    }
                    composited = try RecordingPenCompositor.composite(
                        pixelBuffer,
                        strokes: strokes,
                        pool: pixelBufferAdaptor.pixelBufferPool,
                        contentRect: self.mapsPenToWindowContent ? pixelContentRect : nil
                    )
                } catch {
                    self.failureError = error
                    if !self.didReportFailure {
                        self.didReportFailure = true
                        self.onFailure?(error)
                    }
                    NSLog("[Upshot] Recording live pen compositing failed: \(error.localizedDescription)")
                    return
                }
                if pixelBufferAdaptor.append(composited, withPresentationTime: adjustedPTS) {
                    if !strokes.isEmpty, !self.hasWrittenPen {
                        self.hasWrittenPen = true
                        NSLog("[Upshot] Recording live pen pixels written to screen movie")
                    }
                    self.latestAdjustedTime = adjustedPTS
                } else {
                    _ = self.checkWriterHealth()
                }
            }
        }
    }

    func writeAudioSample(_ sampleBuffer: CMSampleBuffer, kind: ScreenRecordingAudioKind) {
        let sendableSampleBuffer = SendableSampleBuffer(sampleBuffer)
        writingQueue.sync { [weak self, sendableSampleBuffer] in
            autoreleasepool {
                guard let self else { return }

                let input: AVAssetWriterInput?
                switch kind {
                case .system:
                    input = self.systemAudioInput
                case .microphone:
                    input = self.microphoneInput
                }
                guard let input, self.isSessionStarted, !self.isPaused else { return }

                let sampleBuffer = sendableSampleBuffer.sampleBuffer
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let adjustedPTS = self.adjustedTime(time)
                guard adjustedPTS >= .zero,
                      self.checkWriterHealth(),
                      input.isReadyForMoreMediaData,
                      let retimed = Self.retime(sampleBuffer, to: adjustedPTS) else {
                    return
                }
                if !input.append(retimed) {
                    _ = self.checkWriterHealth()
                }
            }
        }
    }

    private func checkWriterHealth() -> Bool {
        guard let assetWriter else { return false }
        guard assetWriter.status == .failed else { return true }

        if failureError == nil {
            failureError = assetWriter.error ?? CocoaError(.fileWriteUnknown)
        }
        if !didReportFailure, let failureError {
            didReportFailure = true
            onFailure?(failureError)
        }
        return false
    }

    func finishWriting() async -> ScreenRecordingWriterResult {
        await withCheckedContinuation { continuation in
            writingQueue.async { [weak self] in
                guard let self, let assetWriter else {
                    continuation.resume(returning: ScreenRecordingWriterResult(
                        url: self?.outputURL,
                        error: nil,
                        sessionStartUptime: nil,
                        duration: 0
                    ))
                    return
                }

                let url = self.outputURL
                let sessionStartUptime = self.sessionStartTime?.seconds
                let duration = self.latestAdjustedTime.seconds
                let priorError = self.failureError

                guard assetWriter.status == .writing else {
                    self.cleanup()
                    continuation.resume(returning: ScreenRecordingWriterResult(
                        url: url,
                        error: priorError ?? assetWriter.error,
                        sessionStartUptime: sessionStartUptime,
                        duration: duration
                    ))
                    return
                }

                self.videoInput?.markAsFinished()
                self.systemAudioInput?.markAsFinished()
                self.microphoneInput?.markAsFinished()
                assetWriter.finishWriting {
                    let error = priorError ?? (assetWriter.status == .completed ? nil : assetWriter.error)
                    self.cleanup()
                    continuation.resume(returning: ScreenRecordingWriterResult(
                        url: url,
                        error: error,
                        sessionStartUptime: sessionStartUptime,
                        duration: duration
                    ))
                }
            }
        }
    }

    func cancel() async {
        await withCheckedContinuation { continuation in
            writingQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }

                if let assetWriter, assetWriter.status == .writing {
                    assetWriter.cancelWriting()
                }
                if let outputURL {
                    try? FileManager.default.removeItem(at: outputURL)
                }
                cleanup()
                continuation.resume()
            }
        }
    }

    private func adjustedTime(_ originalTime: CMTime) -> CMTime {
        var adjusted = originalTime
        if let sessionStartTime {
            adjusted = CMTimeSubtract(adjusted, sessionStartTime)
        }
        if totalPauseDuration > .zero {
            adjusted = CMTimeSubtract(adjusted, totalPauseDuration)
        }
        return adjusted
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

    private func cleanup() {
        latestScreenSample = nil
        hasWrittenPen = false
        assetWriter = nil
        videoInput = nil
        systemAudioInput = nil
        microphoneInput = nil
        pixelBufferAdaptor = nil
        outputURL = nil
        isSessionStarted = false
        sessionStartTime = nil
        isPaused = false
        pauseStartTime = nil
        totalPauseDuration = .zero
        latestAdjustedTime = .zero
        failureError = nil
        didReportFailure = false
    }
}

nonisolated private struct SendableSampleBuffer: @unchecked Sendable {
    let sampleBuffer: CMSampleBuffer

    init(_ sampleBuffer: CMSampleBuffer) {
        self.sampleBuffer = sampleBuffer
    }
}
