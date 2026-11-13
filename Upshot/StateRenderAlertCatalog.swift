import AppKit
import SwiftUI

enum StateRenderAlertCatalog {
    private struct FixtureError: LocalizedError {
        let errorDescription: String?
        init(_ description: String) { errorDescription = description }
    }

    private struct AlertState {
        let name: String
        let source: String
        let marker: String
        let alert: AppAlert
        var fieldText: String? = nil
    }

    static func states() -> [StateRenderDefinition] {
        let diskFull = CocoaError(.fileWriteOutOfSpace)
        let alerts: [AlertState] = [
            AlertState(name: "editor-unsaved", source: "EditorCloseGuard", marker: "beginSheet",
                       alert: EditorCloseGuard.alert(offersDelete: false, projectName: "Release Overview")),
            AlertState(name: "editor-unsaved-project", source: "EditorCloseGuard", marker: "beginSheet",
                       alert: EditorCloseGuard.alert(offersDelete: true, projectName: "Release Overview")),
            AlertState(name: "library-rename", source: "CaptureLibraryView", marker: ".alert(",
                       alert: AppAlerts.libraryRename, fieldText: "Release Overview"),
            AlertState(name: "library-trash", source: "CaptureLibraryView", marker: ".alert(",
                       alert: AppAlerts.libraryTrash(count: 1)),
            AlertState(name: "library-trash-multiple", source: "CaptureLibraryView", marker: ".alert(",
                       alert: AppAlerts.libraryTrash(count: 3)),
            AlertState(name: "library-error", source: "CaptureLibraryView", marker: ".alert(",
                       alert: AppAlerts.libraryActionFailed(message: "“Release Overview.png” couldn’t be opened because it was moved or deleted.")),
            AlertState(name: "cloud-delete", source: "CaptureLibraryInspector", marker: ".alert(",
                       alert: AppAlerts.cloudCopyDeletion),
            AlertState(name: "annotation-delete-style", source: "AnnotationStyleStrip", marker: ".alert(",
                       alert: AppAlerts.styleDeletion(styleName: "Review", owner: .screenshot)),
            AlertState(name: "annotation-delete-style-missing-wallpaper", source: "AnnotationStyleStrip", marker: ".alert(",
                       alert: AppAlerts.styleDeletion(styleName: "Review", owner: .screenshot, wallpaperIsMissing: true)),
            AlertState(name: "studio-delete-style", source: "RecordingStudioLook", marker: ".alert(",
                       alert: AppAlerts.styleDeletion(styleName: "Review", owner: .recording)),
            AlertState(name: "style-imported", source: "AnnotationStyleStrip", marker: ".alert(item: $transferAlert)",
                       alert: AppAlerts.styleImported(importedCount: 2, omittedWallpaperCount: 1, failures: [])),
            AlertState(name: "style-import-error", source: "AnnotationStyleStrip", marker: ".alert(item: $transferAlert)",
                       alert: AppAlerts.styleImported(importedCount: 0, omittedWallpaperCount: 0, failures: ["Review.upshotpreset: The file isn’t in the correct format."])),
            AlertState(name: "style-exported", source: "AnnotationStyleStrip", marker: ".alert(item: $transferAlert)",
                       alert: AppAlerts.styleExported(styleName: "Review", omittedWallpaper: false)),
            AlertState(name: "style-export-error", source: "AnnotationStyleStrip", marker: ".alert(item: $transferAlert)",
                       alert: AppAlerts.styleExportFailed(error: diskFull)),
            AlertState(name: "watermark-import-error", source: "AnnotationWatermarkSourceControls", marker: ".alert(",
                       alert: AppAlerts.watermarkImageFailed(message: CocoaError(.fileReadCorruptFile).localizedDescription)),
            AlertState(name: "studio-media-import-error", source: "RecordingStudioTimelineDock", marker: ".alert(",
                       alert: AppAlerts.studioMediaImportFailed(message: AppAlerts.studioMediaRejectedMessage(fileNames: ["notes.pdf"]))),
            AlertState(name: "studio-reset-clips", source: "RecordingStudioTimelineDock", marker: "struct",
                       alert: AppAlerts.studioClipReset),
            AlertState(name: "capture-name", source: "ScreenshotCaptureNamePrompt", marker: "AppAlerts.screenshotName",
                       alert: AppAlerts.screenshotName, fieldText: "Release Overview"),
            AlertState(name: "screenshot-save-error", source: "CaptureShelf", marker: "NSAlert()",
                       alert: AppAlerts.screenshotSaveFailed(error: diskFull)),
            AlertState(name: "capture-save-error", source: "FailureAlert", marker: "enum FailureAlert",
                       alert: FailureAlert.alert(for: .saveCapture, error: diskFull)),
            AlertState(name: "recording-copy-error", source: "FailureAlert", marker: "enum FailureAlert",
                       alert: FailureAlert.alert(for: .copyRecording, error: FixtureError("The recording file couldn’t be read."))),
            AlertState(name: "recording-project-save-error", source: "FailureAlert", marker: "enum FailureAlert",
                       alert: FailureAlert.alert(for: .saveRecordingProject, error: diskFull)),
            AlertState(name: "recording-input-warning", source: "ScreenRecordingManager", marker: "AppAlerts.recordingInputsUnavailable",
                       alert: AppAlerts.recordingInputsUnavailable(warnings: ["The selected microphone is no longer available, so it was turned off."])),
            AlertState(name: "recording-ended-early", source: "ScreenRecordingManager", marker: "AppAlerts.recordingEndedEarly",
                       alert: AppAlerts.recordingEndedEarly(message: AppAlerts.recordingStoppedMessage(error: FixtureError("The display was disconnected.")))),
            AlertState(name: "recording-save-error", source: "ScreenRecordingManager", marker: "AppAlerts.recordingNotSaved",
                       alert: AppAlerts.recordingNotSaved(message: "The recording destination couldn’t be written.")),
            AlertState(name: "recording-start-error", source: "ScreenRecordingManager", marker: "AppAlerts.recordingStartFailed",
                       alert: AppAlerts.recordingStartFailed(error: FixtureError("The selected display is no longer connected."))),
            AlertState(name: "recording-camera-export-error", source: "RecordingSessionRenderer", marker: "AppAlerts.cameraVideoNotAdded",
                       alert: AppAlerts.cameraVideoNotAdded(error: FixtureError("The export couldn’t be completed."))),
            AlertState(name: "recording-recovered", source: "RecordingRecoveryCoordinator", marker: "AppAlerts.recordingsRecovered",
                       alert: AppAlerts.recordingsRecovered(count: 1)),
            AlertState(name: "recording-recovered-multiple", source: "RecordingRecoveryCoordinator", marker: "AppAlerts.recordingsRecovered",
                       alert: AppAlerts.recordingsRecovered(count: 3)),
            AlertState(name: "screen-recording-permission", source: "ScreenRecordingManager", marker: "AppAlerts.screenRecordingPermission",
                       alert: AppAlerts.screenRecordingPermission),
            AlertState(name: "microphone-permission", source: "RecordingInputAuthorization", marker: "AppAlerts.recordingInputPermission",
                       alert: AppAlerts.recordingInputPermission(.microphone)),
            AlertState(name: "camera-permission", source: "RecordingInputAuthorization", marker: "AppAlerts.recordingInputPermission",
                       alert: AppAlerts.recordingInputPermission(.camera)),
            AlertState(name: "microphone-restricted", source: "RecordingInputAuthorization", marker: "AppAlerts.recordingInputRestricted",
                       alert: AppAlerts.recordingInputRestricted(.microphone)),
            AlertState(name: "automation-confirmation", source: "AutomationURLRouter", marker: "AppAlerts.automationConfirmation",
                       alert: AppAlerts.automationConfirmation(actionTitle: "Share")),
            AlertState(name: "automation-error", source: "AutomationURLRouter", marker: "AppAlerts.automationFailed",
                       alert: AppAlerts.automationFailed(error: AutomationError.message("Unknown Upshot route: capture/unknown"))),
            AlertState(name: "shortcut-action-error", source: "CaptureHotkeys", marker: "AppAlerts.shortcutActionFailed",
                       alert: AppAlerts.shortcutActionFailed(actionTitle: "Capture Previous Area", error: AutomationError.message("No previous area is available."))),
            AlertState(name: "screenshots-folder-error", source: "MenuBarView", marker: "NSAlert()",
                       alert: AppAlerts.screenshotsFolderFailed(directory: URL(fileURLWithPath: "/Volumes/Archive/Screenshots"), errorDescription: nil)),
            AlertState(name: "quit-unsaved", source: "UpshotApp", marker: "AppAlerts.quitWithUnsavedCaptures",
                       alert: AppAlerts.quitWithUnsavedCaptures(captureCount: 1, unsavedProjectCount: 0)),
            AlertState(name: "quit-unsaved-with-projects", source: "UpshotApp", marker: "AppAlerts.quitWithUnsavedCaptures",
                       alert: AppAlerts.quitWithUnsavedCaptures(captureCount: 3, unsavedProjectCount: 1)),
            AlertState(name: "quit-recording", source: "UpshotApp", marker: "AppAlerts.quitDuringRecording",
                       alert: AppAlerts.quitDuringRecording(unsavedCaptureCount: 0)),
            AlertState(name: "quit-recording-with-captures", source: "UpshotApp", marker: "AppAlerts.quitDuringRecording",
                       alert: AppAlerts.quitDuringRecording(unsavedCaptureCount: 2))
        ]
        return alerts.map { state in
            StateRenderDefinition("alert-\(state.name)", source: state.source, marker: state.marker,
                                  size: StateRenderDisplay.size, makeAlert: {
                                      state.alert.makeNSAlert(accessoryView: state.fieldText.map { ScreenshotCaptureNamePrompt.makeNameField(name: $0) })
                                  }) {
                AnyView(EmptyView())
            }
        }
    }
}
