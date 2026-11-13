import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class CaptureHotkeySettingsModel {
    private(set) var shortcuts = CaptureHotkeyPreferences.shortcuts()
    private(set) var recordingAction: CaptureHotkeyAction?
    private(set) var rejectedAttempts: [CaptureHotkeyAction: String] = [:]

    @ObservationIgnored private let recorder = HotkeyShortcutRecorder()

    init() {
        recorder.onShortcutRecorded = { [weak self] shortcut in
            guard let self, let action = self.recordingAction else { return }
            self.apply(shortcut, to: action)
        }
        recorder.onCancel = { [weak self] in
            guard let self, let action = self.recordingAction else { return }
            self.recordingAction = nil
            AppLog.event("settings", "shortcut_recording_cancelled", fields: ["action": action.route])
        }
    }

    func shortcut(for action: CaptureHotkeyAction) -> HotkeyShortcut? {
        shortcuts[action]
    }

    func isRecording(_ action: CaptureHotkeyAction) -> Bool {
        recordingAction == action && recorder.isRecording
    }

    func isCustomized(_ action: CaptureHotkeyAction) -> Bool {
        action.defaultShortcut != nil && shortcut(for: action) != action.defaultShortcut
    }

    func failure(for action: CaptureHotkeyAction) -> String? {
        rejectedAttempts[action] ?? HotkeyManager.shared.registrationErrors[action]
    }

    func toggleRecording(for action: CaptureHotkeyAction) {
        rejectedAttempts[action] = nil
        if isRecording(action) {
            stopRecording()
            AppLog.event("settings", "shortcut_recording_cancelled", fields: ["action": action.route])
            return
        }
        if let previous = recordingAction {
            rejectedAttempts[previous] = nil
        }
        recordingAction = action
        recorder.start()
        AppLog.event("settings", "shortcut_recording_started", fields: ["action": action.route])
    }

    func stopRecording() {
        recorder.stop()
        recordingAction = nil
    }

    func clear(_ action: CaptureHotkeyAction) {
        apply(nil, to: action)
    }

    func reset(_ action: CaptureHotkeyAction) {
        apply(action.defaultShortcut, to: action)
    }

    func reload() {
        shortcuts = CaptureHotkeyPreferences.shortcuts()
    }

    private func apply(_ shortcut: HotkeyShortcut?, to action: CaptureHotkeyAction) {
        recordingAction = nil
        if let shortcut, let conflict = CaptureHotkeyPreferences.conflictingAction(for: shortcut, excluding: action) {
            recorder.stop()
            reject(Self.conflictMessage(for: shortcut, conflict: conflict), for: action, reason: "conflict")
            return
        }
        do {
            try HotkeyManager.shared.setShortcut(shortcut, for: action)
            shortcuts[action] = shortcut
            rejectedAttempts[action] = nil
        } catch {
            reject(error.localizedDescription, for: action, reason: "registration")
        }
    }

    private func reject(_ message: String, for action: CaptureHotkeyAction, reason: String) {
        rejectedAttempts[action] = message
        NSSound.beep()
        AppLog.event("settings", "shortcut_rejected", fields: ["action": action.route, "reason": reason])
    }

    static func conflictMessage(for shortcut: HotkeyShortcut, conflict: CaptureHotkeyAction) -> String {
        "\(shortcut.displayTokens.joined()) is assigned to \(conflict.title)."
    }

    func presentRecordingForRendering(_ action: CaptureHotkeyAction) {
        precondition(UpshotStorage.isRenderingStates)
        recordingAction = action
        recorder.presentRecordingForRendering()
    }

    func presentRejectionForRendering(_ message: String, for action: CaptureHotkeyAction) {
        precondition(UpshotStorage.isRenderingStates)
        rejectedAttempts[action] = message
    }
}

struct CaptureHotkeyShortcutRow: View {
    let action: CaptureHotkeyAction
    let model: CaptureHotkeySettingsModel

    var body: some View {
        let isRecording = model.isRecording(action)
        InterfaceShortcutRow(
            action.title,
            detail: isRecording ? "Include ⌘, ⌥, ⌃, or ⇧. Press Esc to cancel." : nil,
            keys: model.shortcut(for: action)?.displayTokens,
            isRecording: isRecording,
            isCustomized: model.isCustomized(action),
            failure: isRecording ? nil : model.failure(for: action),
            onRecord: { model.toggleRecording(for: action) },
            onClear: { model.clear(action) },
            onReset: { model.reset(action) }
        )
    }
}

struct CaptureHotkeySettingsLifecycle: ViewModifier {
    let model: CaptureHotkeySettingsModel

    func body(content: Content) -> some View {
        content
            .onAppear { model.reload() }
            .onDisappear { model.stopRecording() }
            .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
                model.reload()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
                model.stopRecording()
            }
    }
}

struct CaptureHotkeySettingsSection: View {
    let actions: [CaptureHotkeyAction]
    @State private var model = CaptureHotkeySettingsModel()

    var body: some View {
        InterfaceSection("Keyboard Shortcuts") {
            ForEach(actions) { action in
                CaptureHotkeyShortcutRow(action: action, model: model)
            }
        }
        .modifier(CaptureHotkeySettingsLifecycle(model: model))
    }
}
