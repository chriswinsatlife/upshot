import AppKit
import SwiftUI

struct AppAlertAction: Hashable, Identifiable {
    enum Role: Hashable {
        case standard
        case cancel
        case destructive

        var buttonRole: ButtonRole? {
            switch self {
            case .standard: nil
            case .cancel: .cancel
            case .destructive: .destructive
            }
        }
    }

    let title: String
    let role: Role

    var id: String { title }

    static let ok = AppAlertAction(title: "OK", role: .standard)
    static let cancel = AppAlertAction(title: "Cancel", role: .cancel)
    static let save = AppAlertAction(title: "Save", role: .standard)
    static let doNotSave = AppAlertAction(title: "Don\u{2019}t Save", role: .standard)
    static let delete = AppAlertAction(title: "Delete", role: .standard)
    static let deleteRecording = AppAlertAction(title: "Delete", role: .destructive)
    static let moveToTrash = AppAlertAction(title: "Move to Trash", role: .standard)
    static let rename = AppAlertAction(title: "Rename", role: .standard)
    static let useDefaultName = AppAlertAction(title: "Use Default Name", role: .cancel)
    static let openSystemSettings = AppAlertAction(title: "Open System Settings", role: .standard)
    static let run = AppAlertAction(title: "Run", role: .standard)
    static let continueRecording = AppAlertAction(title: "Continue", role: .standard)
    static let chooseLocation = AppAlertAction(title: "Choose Location\u{2026}", role: .standard)
    static let tryAgain = AppAlertAction(title: "Try Again", role: .standard)
    static let resetClips = AppAlertAction(title: "Reset Clips", role: .standard)
    static let quit = AppAlertAction(title: "Quit", role: .destructive)
    static let finishAndQuit = AppAlertAction(title: "Finish and Quit", role: .standard)
}

struct AppAlert {
    let title: String
    let message: String?
    let actions: [AppAlertAction]
    var returnKeyConfirmsFirstAction = true
    var showsCautionSymbol = false

    func makeNSAlert(accessoryView: NSView? = nil) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = showsCautionSymbol ? .critical : .warning
        alert.messageText = title
        alert.informativeText = message ?? ""
        alert.accessoryView = accessoryView
        for action in actions {
            let button = alert.addButton(withTitle: action.title)
            button.hasDestructiveAction = action.role == .destructive
            if action.role == .cancel {
                button.keyEquivalent = "\u{1b}"
            }
        }
        if !returnKeyConfirmsFirstAction, let first = alert.buttons.first, actions.first?.role != .cancel {
            first.keyEquivalent = ""
        }
        return alert
    }

    func action(for response: NSApplication.ModalResponse) -> AppAlertAction {
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard actions.indices.contains(index) else {
            return actions.first(where: { $0.role == .cancel }) ?? .cancel
        }
        return actions[index]
    }

    @discardableResult
    func runModal(accessoryView: NSView? = nil, initialFirstResponder: NSView? = nil) -> AppAlertAction {
        NSApp.activate(ignoringOtherApps: true)
        let alert = makeNSAlert(accessoryView: accessoryView)
        if let initialFirstResponder {
            alert.window.initialFirstResponder = initialFirstResponder
        }
        AppLog.event("alert", "alert_presented", fields: ["title": title, "presentation": "modal"])
        let chosen = action(for: alert.runModal())
        AppLog.event("alert", "alert_answered", fields: ["title": title, "action": chosen.title])
        return chosen
    }

    func beginSheet(for window: NSWindow, completion: @escaping (AppAlertAction) -> Void) {
        let alert = makeNSAlert()
        AppLog.event("alert", "alert_presented", fields: ["title": title, "presentation": "sheet"])
        alert.beginSheetModal(for: window) { response in
            let chosen = action(for: response)
            AppLog.event("alert", "alert_answered", fields: ["title": title, "action": chosen.title])
            completion(chosen)
        }
    }
}

extension View {
    func appAlert<Item>(
        item: Binding<Item?>,
        alert: @escaping (Item) -> AppAlert,
        perform: @escaping (AppAlertAction, Item) -> Void = { _, _ in }
    ) -> some View {
        self.alert(
            Text(item.wrappedValue.map(alert)?.title ?? ""),
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            presenting: item.wrappedValue
        ) { value in
            ForEach(alert(value).actions) { action in
                Button(action.title, role: action.role.buttonRole) {
                    AppLog.event("alert", "alert_answered", fields: ["title": alert(value).title, "action": action.title])
                    perform(action, value)
                    item.wrappedValue = nil
                }
            }
        } message: { value in
            if let message = alert(value).message {
                Text(message)
            }
        }
    }

    func appAlert(
        isPresented: Binding<Bool>,
        alert: AppAlert,
        perform: @escaping (AppAlertAction) -> Void
    ) -> some View {
        appAlert(
            item: Binding(
                get: { isPresented.wrappedValue ? alert.title : nil },
                set: { if $0 == nil { isPresented.wrappedValue = false } }
            ),
            alert: { _ in alert },
            perform: { action, _ in perform(action) }
        )
    }
}

enum AppAlerts {
    enum StyleOwner {
        case screenshot
        case recording
    }

    enum RecordingInput {
        case camera
        case microphone

        var title: String {
            switch self {
            case .camera: "Camera"
            case .microphone: "Microphone"
            }
        }
    }

    static func editorUnsavedChanges(projectName: String) -> AppAlert {
        AppAlert(
            title: "Save Changes to \u{201C}\(projectName)\u{201D}?",
            message: "Your changes will be lost if you don\u{2019}t save them.",
            actions: [.save, .doNotSave, .cancel]
        )
    }

    static func editorUnsavedNewRecording(projectName: String) -> AppAlert {
        AppAlert(
            title: projectName.isEmpty ? "Save Recording?" : "Save \u{201C}\(projectName)\u{201D}?",
            message: "This recording was never saved, so deleting it also deletes its footage.",
            actions: [.save, .deleteRecording, .cancel]
        )
    }

    static let libraryRename = AppAlert(
        title: "Rename Capture",
        message: nil,
        actions: [.rename, .cancel]
    )

    static func libraryTrash(count: Int) -> AppAlert {
        AppAlert(
            title: count == 1 ? "Move Capture to Trash?" : "Move \(count) Captures to Trash?",
            message: "Exported copies and cloud links stay available.",
            actions: [.moveToTrash, .cancel]
        )
    }

    static func libraryActionFailed(message: String) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Complete Library Action",message: message, actions: [.ok])
    }

    static let cloudCopyDeletion = AppAlert(
        title: "Delete Cloud Copy?",
        message: "Its share link stops working, and the capture stays in the Library.",
        actions: [.delete, .cancel]
    )

    static func styleDeletion(styleName: String, owner: StyleOwner, wallpaperIsMissing: Bool = false) -> AppAlert {
        let unchanged = owner == .screenshot ? "This screenshot doesn\u{2019}t change." : "This recording doesn\u{2019}t change."
        return AppAlert(
            title: "Delete \u{201C}\(styleName)\u{201D} Style?",
            message: wallpaperIsMissing ? "Its wallpaper file is missing, so it can\u{2019}t be applied." : unchanged,
            actions: [.delete, .cancel]
        )
    }

    static func styleImported(importedCount: Int, omittedWallpaperCount: Int, failures: [String]) -> AppAlert {
        guard importedCount > 0 else {
            return AppAlert(title: "Couldn\u{2019}t Import Styles", message: failures.joined(separator: "\n"), actions: [.ok])
        }
        var lines: [String] = []
        if omittedWallpaperCount > 0 {
            lines.append(omittedWallpaperCount == 1
                ? "1 local wallpaper wasn\u{2019}t included, so it uses no background."
                : "\(omittedWallpaperCount) local wallpapers weren\u{2019}t included, so they use no background.")
        }
        lines.append(contentsOf: failures)
        return AppAlert(
            title: importedCount == 1 ? "Style Imported" : "\(importedCount) Styles Imported",
            message: lines.isEmpty ? nil : lines.joined(separator: "\n"),
            actions: [.ok]
        )
    }

    static func styleExported(styleName: String, omittedWallpaper: Bool) -> AppAlert {
        AppAlert(
            title: "Style Exported",
            message: omittedWallpaper
                ? "The local wallpaper wasn\u{2019}t included, so the style uses no background."
                : "\u{201C}\(styleName)\u{201D} is ready to share.",
            actions: [.ok]
        )
    }

    static func styleExportFailed(error: Error) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Export Style", message: error.localizedDescription, actions: [.ok])
    }

    static func watermarkImageFailed(message: String) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Use Watermark Image", message: message, actions: [.ok])
    }

    static func studioMediaImportFailed(message: String) -> AppAlert {
        AppAlert(title: "Some Files Weren\u{2019}t Added", message: message, actions: [.ok])
    }

    static let studioClipReset = AppAlert(
        title: "Reset All Clip Edits?",
        message: "You can undo this.",
        actions: [.resetClips, .cancel]
    )

    static let screenshotName = AppAlert(
        title: "Name Screenshot",
        message: nil,
        actions: [.save, .useDefaultName]
    )

    static func screenshotSaveFailed(error: Error) -> AppAlert {
        AppAlert(
            title: "Couldn\u{2019}t Save Screenshot",
            message: error.localizedDescription,
            actions: [.chooseLocation, .tryAgain, .cancel]
        )
    }

    static func operationFailed(title: String, error: Error, detail: String?) -> AppAlert {
        AppAlert(
            title: title,
            message: [error.localizedDescription, detail].compactMap { $0 }.joined(separator: " "),
            actions: [.ok]
        )
    }

    static func recordingInputsUnavailable(warnings: [String]) -> AppAlert {
        AppAlert(
            title: "Recording Inputs Unavailable",
            message: warnings.joined(separator: "\n"),
            actions: [.continueRecording]
        )
    }

    static func recordingStoppedMessage(error: Error) -> String {
        "\(error.localizedDescription) Everything recorded until then was saved."
    }

    static func studioMediaRejectedMessage(fileNames: [String]) -> String {
        let names = ListFormatter.localizedString(byJoining: fileNames)
        return fileNames.count == 1
            ? "\(names) isn\u{2019}t an image, GIF, or audio file."
            : "\(names) aren\u{2019}t images, GIFs, or audio files."
    }

    static func recordingEndedEarly(message: String) -> AppAlert {
        AppAlert(title: "Recording Ended Early", message: message, actions: [.ok])
    }

    static func recordingNotSaved(message: String) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Save Recording", message: message, actions: [.ok])
    }

    static func recordingStartFailed(error: Error) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Start Recording", message: error.localizedDescription, actions: [.ok])
    }

    static func cameraVideoNotAdded(error: Error) -> AppAlert {
        AppAlert(
            title: "Couldn\u{2019}t Add Camera Video",
            message: "\(error.localizedDescription) The screen, camera, and audio tracks are still in the recording project.",
            actions: [.ok]
        )
    }

    static func recordingsRecovered(count: Int) -> AppAlert {
        AppAlert(
            title: count == 1 ? "Recording Recovered" : "\(count) Recordings Recovered",
            message: count == 1
                ? "An interrupted recording is back in History, ready to open in Studio."
                : "Interrupted recordings are back in History, ready to open in Studio.",
            actions: [.ok]
        )
    }

    static let screenRecordingPermission = AppAlert(
        title: "Allow Screen Recording",
        message: "Turn on Upshot in Privacy & Security > Screen & System Audio Recording, then reopen Upshot.",
        actions: [.openSystemSettings, .cancel]
    )

    static func recordingInputPermission(_ input: RecordingInput) -> AppAlert {
        AppAlert(
            title: "Allow \(input.title) Access",
            message: "Turn on Upshot in Privacy & Security > \(input.title), then select the \(input.title.lowercased()) again.",
            actions: [.openSystemSettings, .cancel]
        )
    }

    static func recordingInputRestricted(_ input: RecordingInput) -> AppAlert {
        AppAlert(
            title: "\(input.title) Access Restricted",
            message: "This Mac doesn\u{2019}t allow Upshot to use the \(input.title.lowercased()).",
            actions: [.ok]
        )
    }

    static func automationConfirmation(actionTitle: String) -> AppAlert {
        AppAlert(
            title: "Run \u{201C}\(actionTitle)\u{201D} from a Link?",
            message: "Another app or a web page opened an Upshot link for this action.",
            actions: [.run, .cancel],
            returnKeyConfirmsFirstAction: false
        )
    }

    static func automationFailed(error: Error) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Run Link Action", message: error.localizedDescription, actions: [.ok])
    }

    static func shortcutActionFailed(actionTitle: String, error: Error) -> AppAlert {
        AppAlert(title: "Couldn\u{2019}t Run \u{201C}\(actionTitle)\u{201D}", message: error.localizedDescription, actions: [.ok])
    }

    static func screenshotsFolderFailed(directory: URL, errorDescription: String?) -> AppAlert {
        AppAlert(
            title: "Couldn\u{2019}t Open Screenshots Folder",
            message: errorDescription ?? (directory.path as NSString).abbreviatingWithTildeInPath,
            actions: [.ok]
        )
    }

    static func quitWithUnsavedCaptures(captureCount: Int, unsavedProjectCount: Int) -> AppAlert {
        AppAlert(
            title: captureCount == 1 ? "Quit with 1 Unsaved Capture?" : "Quit with \(captureCount) Unsaved Captures?",
            message: unsavedProjectCount > 0
                ? "Unsaved captures are deleted, and recording edits are kept."
                : "Unsaved captures are deleted when Upshot quits.",
            actions: [.quit, .cancel],
            returnKeyConfirmsFirstAction: false,
            showsCautionSymbol: true
        )
    }

    static func quitDuringRecording(unsavedCaptureCount: Int) -> AppAlert {
        AppAlert(
            title: "Finish Recording and Quit?",
            message: unsavedCaptureCount == 0
                ? "The recording is saved before Upshot quits."
                : "The recording is saved, and \(unsavedCaptureCount == 1 ? "1 unsaved capture is" : "\(unsavedCaptureCount) unsaved captures are") deleted.",
            actions: [.finishAndQuit, .cancel],
            returnKeyConfirmsFirstAction: unsavedCaptureCount == 0
        )
    }
}
