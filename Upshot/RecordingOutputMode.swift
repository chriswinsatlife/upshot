import AppKit
import Foundation

enum RecordingOutputMode: String, CaseIterable, Sendable {
    case video
    case gif
    case studio

    var title: String {
        switch self {
        case .video: "Record Video"
        case .gif: "Record GIF"
        case .studio: "Record in Studio Mode"
        }
    }

    var systemImage: String {
        switch self {
        case .video: "video.fill"
        case .gif: "photo.stack"
        case .studio: "film"
        }
    }

    var keyHint: String {
        switch self {
        case .video: "↩"
        case .gif: "⌥↩"
        case .studio: "⇧↩"
        }
    }

    static func forReturnKey(modifierFlags: NSEvent.ModifierFlags) -> RecordingOutputMode {
        let flags = modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.option) { return .gif }
        if flags.contains(.shift) { return .studio }
        return .video
    }
}

@MainActor
final class RecordingOutputModeCoordinator {
    static let shared = RecordingOutputModeCoordinator()

    private(set) var pendingMode: RecordingOutputMode?
    private(set) var activeMode: RecordingOutputMode = .video
    private var isFinishHandlerInstalled = false

    private init() {}

    func record(_ mode: RecordingOutputMode) {
        let area = RecordingAreaSelectionPresenter.shared
        guard area.isActive, area.selection != nil else {
            AppLog.event("recording", "recording_output_mode_rejected", fields: ["mode": mode.rawValue, "reason": "no_area_selection"])
            NSSound.beep()
            return
        }
        pendingMode = mode
        AppLog.event("recording", "recording_output_mode_selected", fields: ["mode": mode.rawValue])
        area.commit()
        if area.isActive {
            pendingMode = nil
            AppLog.event("recording", "recording_output_mode_rejected", fields: ["mode": mode.rawValue, "reason": "area_commit_failed"])
        }
    }

    func setPendingMode(_ mode: RecordingOutputMode) {
        pendingMode = mode
        AppLog.event("recording", "recording_output_mode_selected", fields: ["mode": mode.rawValue])
    }

    func clearPendingMode() {
        pendingMode = nil
    }

    func beginSession() {
        activeMode = pendingMode ?? .video
        pendingMode = nil
        AppLog.event("recording", "recording_output_mode_started", fields: ["mode": activeMode.rawValue])
        if activeMode != .video {
            installFinishHandlerIfNeeded()
        }
    }

    private func installFinishHandlerIfNeeded() {
        guard !isFinishHandlerInstalled else { return }
        isFinishHandlerInstalled = true
        let manager = ScreenRecordingManager.shared
        let previousHandler = manager.onFinishRecording
        manager.onFinishRecording = { session, displayID in
            previousHandler?(session, displayID)
            RecordingOutputModeCoordinator.shared.finish(session: session, displayID: displayID)
        }
    }

    private func finish(session: RecordingSession, displayID: CGDirectDisplayID?) {
        let mode = activeMode
        activeMode = .video
        AppLog.event("recording", "recording_output_mode_finished", fields: ["mode": mode.rawValue])
        switch mode {
        case .video:
            break
        case .studio:
            RecordingProjectOpener.shared.open(session)
            AppLog.event("recording", "recording_studio_mode_opened", fields: ["session": session.directoryURL.lastPathComponent])
        case .gif:
            Task { await exportGIF(session: session, displayID: displayID) }
        }
    }

    private func exportGIF(session: RecordingSession, displayID: CGDirectDisplayID?) async {
        var options = UpshotPreferences.recordingExtendedExportDefaults
        options.format = .gif
        let started = ContinuousClock.now
        let sourceURL = session.deliverableURL
        AppLog.event("recording", "recording_gif_export_started", fields: ["session": session.directoryURL.lastPathComponent, "fps": String(options.gifFrameRate.rawValue), "quality": options.gifQuality.rawValue, "optimized": String(options.optimizesGIF)])
        do {
            let exportedURL = try await RecordingGIFExporter.export(videoURL: sourceURL, options: options) { _ in }
            let namedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(session.directoryURL.deletingPathExtension().lastPathComponent)
                .appendingPathExtension("gif")
            try FileManager.default.createDirectory(at: namedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: exportedURL, to: namedURL)
            defer { try? FileManager.default.removeItem(at: namedURL.deletingLastPathComponent()) }
            let historyURL = ScreenshotHistoryStore.shared.importScreenshot(from: namedURL)
            CaptureShelf.shared.add(url: historyURL)
            if AfterCaptureActions.isEnabled(.showOverlay, for: .screenshot) {
                CaptureShelfPresenter.shared.show(displayID: displayID)
            }
            AppLog.event("recording", "recording_gif_export_completed", fields: ["outcome": "success", "file": historyURL.lastPathComponent, "duration": String(describing: started.duration(to: .now))])
        } catch {
            AppLog.event("recording", "recording_gif_export_completed", fields: ["outcome": "failed", "error": AppLog.error(error), "duration": String(describing: started.duration(to: .now))])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "GIF export failed", displayID: displayID)
        }
    }
}
