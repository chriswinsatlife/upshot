import AppKit
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

nonisolated enum AutomationError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self { case .message(let message): message }
    }
}

enum AutomationActions {
    static var capturePreviousArea: (() async throws -> URL)?
    private static var captureInProgress = false

    static func perform(_ action: CaptureHotkeyAction, parameters: [String: String] = [:]) async throws -> JSONValue {
        NSLog("Automation action started action=%@", action.route)
        do {
            let result = try await execute(action, parameters: parameters)
            NSLog("Automation action completed action=%@", action.route)
            return result
        } catch {
            NSLog("Automation action failed action=%@ error=%@", action.route, error.localizedDescription)
            throw error
        }
    }

    private static func execute(_ action: CaptureHotkeyAction, parameters: [String: String]) async throws -> JSONValue {
        if action.route.hasPrefix("capture/") {
            guard !captureInProgress else { throw AutomationError.message("Another automation capture is in progress.") }
            captureInProgress = true
            defer { captureInProgress = false }
            return try await capture(action, parameters: parameters)
        }
        let manager = ScreenRecordingManager.shared
        switch action {
        case .screenRecording:
            RecordingPickerPresenter.shared.show()
        case .recordingStart where !manager.isActive, .recordingToggle where !manager.isActive:
            guard !manager.isActive else { throw AutomationError.message("A recording is already active.") }
            let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
            let content = try await ScreenRecordingCapture.availableContent()
            guard let display = content.displays.first(where: { $0.displayID == displayID }) ?? content.displays.first else {
                throw AutomationError.message("No display is available to record.")
            }
            guard await CaptureCountdownPresenter.shared.runIfNeeded(seconds: UpshotPreferences.recordingStartDelaySeconds, displayID: display.displayID) else {
                throw CancellationError()
            }
            guard !manager.isActive else { throw AutomationError.message("A recording is already active.") }
            manager.startRecording(source: ScreenRecordingSource(kind: .fullscreen(display)))
        case .recordingStart:
            throw AutomationError.message("A recording is already active.")
        case .recordingStop, .recordingToggle:
            try requireRecordingState([.recording, .paused])
            manager.stopRecording()
        case .recordingPause:
            try requireRecordingState([.recording])
            manager.pauseRecording()
        case .recordingResume:
            try requireRecordingState([.paused])
            manager.resumeRecording()
        case .recordingRestart:
            try requireRecordingState([.recording, .paused])
            manager.restartRecording()
        case .recordingDiscard:
            try requireRecordingState([.recording, .paused])
            manager.deleteRecording()
        case .editorOpen:
            let url = try editorURL(parameters["path"], video: false)
            guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true else {
                throw AutomationError.message("The screenshot editor requires an image file.")
            }
            guard let open = CaptureShelfPresenter.shared.onAnnotate else { throw AutomationError.message("The screenshot editor is not ready.") }
            let historyURL = ScreenshotHistoryStore.shared.importScreenshot(from: url)
            open(historyURL)
        case .recordingEditorOpen:
            let url = try editorURL(parameters["path"], video: true)
            guard RecordingSession.isSessionDirectory(url) || UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) == true else {
                throw AutomationError.message("The recording editor requires a recording project or video file.")
            }
            guard let open = RecordingProjectOpener.shared.openHandler else { throw AutomationError.message("The recording editor is not ready.") }
            open(url)
        case .library: CaptureLibraryModel.shared.show(filter: .all)
        case .libraryScreenshots: CaptureLibraryModel.shared.show(filter: .screenshots)
        case .libraryRecordings: CaptureLibraryModel.shared.show(filter: .recordings)
        case .libraryRefresh: CaptureLibraryModel.shared.refresh()
        case .libraryPreview, .libraryEdit, .libraryRename, .libraryCopy, .libraryExport, .libraryReveal, .libraryTrash:
            let library = CaptureLibraryModel.shared
            guard !library.isBusy, !library.selectedItems.isEmpty else {
                throw AutomationError.message("Select captures in an idle Library before using this action.")
            }
            let operation: CaptureLibraryAction
            switch action {
            case .libraryPreview: operation = .preview
            case .libraryEdit: operation = .edit
            case .libraryRename: operation = .rename
            case .libraryCopy: operation = .copy
            case .libraryExport: operation = .export
            case .libraryReveal: operation = .reveal
            default: operation = .trash
            }
            if [.libraryPreview, .libraryEdit, .libraryRename].contains(action), library.selectedItems.count != 1 {
                throw AutomationError.message("This Library action requires exactly one selected capture.")
            }
            library.perform(operation)
        case .editorSave, .editorSaveCopy, .editorDone, .editorShare, .editorUndo, .editorRedo:
            try AutomationEditorActions.perform(action)
        case .recordingEditorSave, .recordingEditorUndo, .recordingEditorRedo, .recordingEditorPlay, .recordingEditorPause,
             .recordingEditorExport, .recordingEditorExportAudio, .recordingEditorCancelExport:
            let url = try editorURL(parameters["path"], video: true)
            guard let model = StudioProjectRegistry.shared.editorModel(for: url), model.isLoaded else {
                throw AutomationError.message("Open the recording project in its editor before using this action.")
            }
            if action != .recordingEditorCancelExport, model.exportState.isExporting || model.shareState.isBusy {
                throw AutomationError.message("The recording editor is exporting or sharing.")
            }
            switch action {
            case .recordingEditorSave:
                guard model.saveProject() else { throw AutomationError.message("The recording project could not be saved.") }
            case .recordingEditorUndo: model.undo()
            case .recordingEditorRedo: model.redo()
            case .recordingEditorPlay: model.play()
            case .recordingEditorPause: model.pause()
            case .recordingEditorExport: model.export()
            case .recordingEditorExportAudio:
                guard model.hasAudio else { throw AutomationError.message("The recording has no audio to export.") }
                model.exportAudio()
            default: model.cancelExport()
            }
        case .restoreLastCapture:
            ScreenshotHistoryStore.shared.reload()
            guard let item = ScreenshotHistoryStore.shared.recentItems.first else { throw AutomationError.message("Capture history is empty.") }
            CaptureShelf.shared.show(existing: item.url, kind: item.isVideo ? .video : .image)
            CaptureShelfPresenter.shared.show(displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: false))
        case .settings, .settingsScreenshots, .settingsVideo, .settingsOverlay, .settingsMCP, .settingsCloud, .settingsAbout:
            guard let tab = SettingsTab(rawValue: String(action.route.split(separator: "/").last!)) else {
                throw AutomationError.message("Unknown settings tab.")
            }
            SettingsWindowController.show(tab: tab)
        case .screenshotsFolder:
            let directory = UpshotPreferences.exportDirectory
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard NSWorkspace.shared.open(directory) else { throw AutomationError.message("The screenshots folder could not be opened.") }
        default: throw AutomationError.message("Unsupported action: \(action.route)")
        }
        return ["action": .string(action.route), "status": "accepted"]
    }

    private static func requireRecordingState(_ states: [ScreenRecordingState]) throws {
        guard states.contains(ScreenRecordingManager.shared.state) else {
            throw AutomationError.message("The current recording state does not allow this action.")
        }
    }

    private static func editorURL(_ path: String?, video: Bool) throws -> URL {
        if let path {
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { throw AutomationError.message("The editor file does not exist.") }
            return url
        }
        ScreenshotHistoryStore.shared.reload()
        guard let item = ScreenshotHistoryStore.shared.recentItems.first(where: { $0.isVideo == video }) else {
            throw AutomationError.message(video ? "No recording exists in history." : "No screenshot exists in history.")
        }
        return item.editorURL
    }

    private static func capture(_ action: CaptureHotkeyAction, parameters: [String: String]) async throws -> JSONValue {
        if action == .textCapture {
            let text: String
            switch await CaptureCoordinator.shared.captureTextAwaiting() {
            case .copied(let recognized): text = recognized
            case .cancelled: throw AutomationError.message("Text capture was cancelled or failed.")
            case .noTextFound: throw AutomationError.message("No text was recognized.")
            }
            if let output = parameters["output"] {
                let destination = URL(fileURLWithPath: output)
                try Data(text.utf8).write(to: destination, options: .withoutOverwriting)
                return ["path": .string(destination.path), "text": .string(text)]
            }
            return ["text": .string(text)]
        }
        let captured: URL?
        switch action {
        case .fullscreen: captured = await CaptureCoordinator.shared.captureFullscreenAwaiting()
        case .window: captured = await CaptureCoordinator.shared.captureWindowAwaiting()
        case .area: captured = await CaptureCoordinator.shared.captureAreaAwaiting()
        case .previousArea:
            guard let capturePreviousArea else { throw AutomationError.message("Capture Previous Area requires the area-selection integration.") }
            captured = try await capturePreviousArea()
        case .areaCopy, .areaSave, .areaUpload, .selfTimer:
            if action == .areaUpload, !CloudUploader.shared.isConfigured { throw CloudUploadError.notConfigured }
            let seconds: Int
            if action == .selfTimer {
                guard let delay = Int(parameters["delay"] ?? "5"), (1...3600).contains(delay) else {
                    throw AutomationError.message("Self-timer delay must be between 1 and 3600 seconds.")
                }
                seconds = delay
            } else { seconds = UpshotPreferences.captureDelaySeconds }
            let probe = CaptureSourceProbe(tracksPointer: true)
            if let raw = await ScreenshotManager.shared.captureArea(includeShadow: UpshotPreferences.captureWindowShadow, delaySeconds: seconds) {
                captured = ScreenshotHistoryStore.shared.importScreenshot(from: raw, source: probe.finish(.area))
            } else { captured = nil }
        default: throw AutomationError.message("Unsupported capture action.")
        }
        guard let captured else { throw AutomationError.message("Screenshot capture was cancelled or failed.") }
        var result: [String: JSONValue] = ["path": .string(captured.path)]
        switch action {
        case .areaCopy: try ScreenshotFileActions.copyImageToClipboard(from: captured)
        case .areaSave: result["path"] = .string(try ScreenshotFileActions.saveToDefaultLocation(from: captured).path)
        case .areaUpload:
            let upload = try await CloudUploader.shared.upload(itemID: UUID(), fileURL: captured)
            ScreenshotHistoryStore.shared.setCloudURL(for: captured, cloudURL: upload.url)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(upload.url, forType: .string)
            result["url"] = .string(upload.url)
        default: break
        }
        if let output = parameters["output"] {
            let destination = URL(fileURLWithPath: output)
            guard destination.pathExtension.lowercased() == "png" else { throw AutomationError.message("Screenshot output requires a .png extension.") }
            try FileManager.default.copyItem(at: captured, to: destination)
            result["path"] = .string(destination.path)
        }
        if action == .selfTimer {
            CaptureShelf.shared.add(url: captured)
        }
        if [.areaCopy, .areaSave, .areaUpload].contains(action),
           AfterCaptureActions.isEnabled(.showOverlay, for: .screenshot) {
            CaptureShelf.shared.show(existing: captured, kind: .image)
        }
        if [.areaCopy, .areaSave, .areaUpload, .selfTimer].contains(action),
           AfterCaptureActions.isEnabled(.showOverlay, for: .screenshot) {
            CaptureShelfPresenter.shared.show(displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
        }
        NSLog("Automation capture completed action=%@ path=%@", action.route, result["path"]?.stringValue ?? captured.path)
        return .object(result)
    }
}
