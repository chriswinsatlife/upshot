import AppIntents
import ScreenCaptureKit

nonisolated enum UpshotIntentError: Error, CustomLocalizedStringResourceConvertible {
    case captureCancelled
    case captureFailed
    case recognitionFailed
    case noTextRecognized
    case recordingAlreadyActive
    case noActiveRecording
    case noDisplayAvailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .captureCancelled:
            "The screenshot was cancelled before it could be captured."
        case .captureFailed:
            "Capture failed. The selected area could not be captured."
        case .recognitionFailed:
            "Text recognition failed. The captured image could not be recognized."
        case .noTextRecognized:
            "No text was recognized in the captured area."
        case .recordingAlreadyActive:
            "Upshot is already recording."
        case .noActiveRecording:
            "Upshot isn't currently recording."
        case .noDisplayAvailable:
            "No display was available to record."
        }
    }
}

nonisolated struct TakeFullScreenScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Full Screen Screenshot"
    static var description = IntentDescription(
        "Captures the entire screen and adds it to Upshot's history."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let url = await CaptureCoordinator.shared.captureFullscreenAwaiting() else {
            throw UpshotIntentError.captureCancelled
        }
        return .result(value: IntentFile(fileURL: url))
    }
}

nonisolated struct TakeWindowScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Window Screenshot"
    static var description = IntentDescription(
        "Captures a window you click and adds it to Upshot's history."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let url = await CaptureCoordinator.shared.captureWindowAwaiting() else {
            throw UpshotIntentError.captureCancelled
        }
        return .result(value: IntentFile(fileURL: url))
    }
}

nonisolated struct TakeAreaScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "Take Area Screenshot"
    static var description = IntentDescription(
        "Captures a region you drag out and adds it to Upshot's history."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        guard let url = await CaptureCoordinator.shared.captureAreaAwaiting() else {
            throw UpshotIntentError.captureCancelled
        }
        return .result(value: IntentFile(fileURL: url))
    }
}

nonisolated struct CaptureTextIntent: AppIntent {
    static var title: LocalizedStringResource = "Capture Text"
    static var description = IntentDescription(
        "Recognizes the text inside a region you drag out, copies it to the clipboard, and returns it."
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        switch await CaptureCoordinator.shared.captureTextAwaiting() {
        case .cancelled:
            throw UpshotIntentError.captureCancelled
        case .noTextFound:
            throw UpshotIntentError.noTextRecognized
        case .captureFailed:
            AppLog.event("application", "capture_text_intent_failed_capture_failed")
            throw UpshotIntentError.captureFailed
        case .recognitionFailed:
            AppLog.event("application", "capture_text_intent_failed_text_recognition_failed")
            throw UpshotIntentError.recognitionFailed
        case .copied(let text):
            return .result(value: text)
        }
    }
}

@MainActor
private func startFullScreenRecording() async throws {
    guard !ScreenRecordingManager.shared.isActive else {
        throw UpshotIntentError.recordingAlreadyActive
    }
    let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
    guard let content = try? await ScreenRecordingCapture.availableContent(),
          let display = content.displays.first(where: { $0.displayID == displayID })
            ?? content.displays.first else {
        throw UpshotIntentError.noDisplayAvailable
    }
    CaptureCoordinator.shared.recordFullscreen(display)
}

nonisolated struct StartScreenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Screen Recording"
    static var description = IntentDescription(
        "Starts recording the active display in Upshot."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        try await startFullScreenRecording()
        return .result()
    }
}

nonisolated struct StopScreenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Screen Recording"
    static var description = IntentDescription(
        "Stops the current Upshot screen recording."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        guard ScreenRecordingManager.shared.isActive else {
            throw UpshotIntentError.noActiveRecording
        }
        ScreenRecordingManager.shared.stopRecording()
        return .result()
    }
}

nonisolated struct ToggleScreenRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Screen Recording"
    static var description = IntentDescription(
        "Starts a full screen recording if Upshot is idle, or stops the current one."
    )

    @MainActor
    func perform() async throws -> some IntentResult {
        if ScreenRecordingManager.shared.isActive {
            ScreenRecordingManager.shared.stopRecording()
        } else {
            try await startFullScreenRecording()
        }
        return .result()
    }
}

nonisolated struct UpshotShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TakeFullScreenScreenshotIntent(),
            phrases: [
                "Take a screenshot with \(.applicationName)",
                "Capture the screen with \(.applicationName)"
            ],
            shortTitle: "Take Full Screen Screenshot",
            systemImageName: "camera.viewfinder"
        )
        AppShortcut(
            intent: TakeWindowScreenshotIntent(),
            phrases: [
                "Take a window screenshot with \(.applicationName)"
            ],
            shortTitle: "Take Window Screenshot",
            systemImageName: "macwindow"
        )
        AppShortcut(
            intent: TakeAreaScreenshotIntent(),
            phrases: [
                "Take an area screenshot with \(.applicationName)"
            ],
            shortTitle: "Take Area Screenshot",
            systemImageName: "crop"
        )
        AppShortcut(
            intent: CaptureTextIntent(),
            phrases: [
                "Capture text with \(.applicationName)",
                "Copy text from the screen with \(.applicationName)"
            ],
            shortTitle: "Capture Text",
            systemImageName: "text.viewfinder"
        )
        AppShortcut(
            intent: StartScreenRecordingIntent(),
            phrases: [
                "Start recording with \(.applicationName)",
                "Start a screen recording with \(.applicationName)"
            ],
            shortTitle: "Start Screen Recording",
            systemImageName: "record.circle"
        )
        AppShortcut(
            intent: StopScreenRecordingIntent(),
            phrases: [
                "Stop recording with \(.applicationName)",
                "Stop the screen recording with \(.applicationName)"
            ],
            shortTitle: "Stop Screen Recording",
            systemImageName: "stop.circle"
        )
        AppShortcut(
            intent: ToggleScreenRecordingIntent(),
            phrases: [
                "Toggle screen recording with \(.applicationName)"
            ],
            shortTitle: "Toggle Screen Recording",
            systemImageName: "record.circle.fill"
        )
    }
}
