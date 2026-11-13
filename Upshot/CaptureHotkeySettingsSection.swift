import AppKit
import SwiftUI

struct CaptureHotkeySettingsSection: View {
    let actions: [CaptureHotkeyAction]
    @State private var searchText = ""
    @State private var showsAllActions = UpshotStorage.isRenderingStates && StateRenderer.scenario == "settings-shortcuts-expanded"

    @State private var shortcuts = CaptureHotkeyPreferences.shortcuts()
    @State private var recorder = HotkeyShortcutRecorder()
    @State private var recordingAction: CaptureHotkeyAction?
    @State private var errorMessage: String?

    var body: some View {
        Section("Keyboard Shortcuts") {
            TextField("Search all shortcuts", text: $searchText)
                .textFieldStyle(.roundedBorder)
            Toggle("Show all actions", isOn: $showsAllActions)
            ForEach(visibleActions) { action in
                LabeledContent(action.title) {
                    HStack(spacing: 8) {
                        if shortcut(for: action) != action.defaultShortcut, !isRecording(action) {
                            InspectorResetButton(help: "Restore the default shortcut") {
                                resetShortcut(for: action)
                            }
                            .transition(.blurPop)
                        }

                        ZStack {
                            if isRecording(action) {
                                Text("Press keys…")
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .phaseAnimator([1.0, 0.45]) { content, opacity in
                                        content.opacity(opacity)
                                    } animation: { _ in .easeInOut(duration: 0.7) }
                                    .transition(.blurPop)
                            } else {
                                KeyCaps(tokens: shortcut(for: action)?.displayTokens ?? ["Unassigned"])
                                    .transition(.blurPop)
                            }
                        }

                        if shortcut(for: action) != nil, !isRecording(action) {
                            InterfaceActionButton("Clear") { apply(nil, to: action) }
                        }
                        InterfaceActionButton(isRecording(action) ? "Cancel" : "Record") {
                            toggleRecording(for: action)
                        }
                    }
                    .motion(.morphQuick, value: isRecording(action))
                    .motion(.morphQuick, value: shortcut(for: action))
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Palette.record)
            }

            ForEach(visibleActions) { action in
                if let failure = HotkeyManager.shared.registrationErrors[action] {
                    Text("\(action.title): \(failure)")
                        .font(.caption)
                        .foregroundStyle(Palette.record)
                }
            }

            if recordingAction != nil {
                Text("Press a key combination with at least one modifier. Press Esc to cancel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            reloadShortcuts()
            configureRecorder()
        }
        .onDisappear {
            recorder.stop()
            recordingAction = nil
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            reloadShortcuts()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
            recorder.stop()
            recordingAction = nil
        }
    }

    private var visibleActions: [CaptureHotkeyAction] {
        let catalog = showsAllActions || !searchText.isEmpty ? CaptureHotkeyAction.allCases : actions
        return catalog.filter { searchText.isEmpty || $0.title.localizedStandardContains(searchText) || $0.route.localizedStandardContains(searchText) }
    }

    private func shortcut(for action: CaptureHotkeyAction) -> HotkeyShortcut? {
        shortcuts[action]
    }

    private func isRecording(_ action: CaptureHotkeyAction) -> Bool {
        recorder.isRecording && recordingAction == action
    }

    private func toggleRecording(for action: CaptureHotkeyAction) {
        errorMessage = nil

        if isRecording(action) {
            recorder.stop()
            recordingAction = nil
            return
        }

        recordingAction = action
        recorder.start()
    }

    private func resetShortcut(for action: CaptureHotkeyAction) {
        apply(action.defaultShortcut, to: action)
    }

    private func configureRecorder() {
        recorder.onShortcutRecorded = { shortcut in
            guard let recordingAction else { return }
            apply(shortcut, to: recordingAction)
        }

        recorder.onCancel = {
            recordingAction = nil
        }
    }

    private func apply(_ shortcut: HotkeyShortcut?, to action: CaptureHotkeyAction) {
        if let shortcut, let conflict = CaptureHotkeyPreferences.conflictingAction(for: shortcut, excluding: action) {
            errorMessage = "\(shortcut.displayString) is already assigned to \(conflict.title)."
            NSSound.beep()
            recorder.stop()
            recordingAction = nil
            return
        }

        do {
            try HotkeyManager.shared.setShortcut(shortcut, for: action)
            shortcuts[action] = shortcut
            errorMessage = nil
        } catch {
            errorMessage = "\(error.localizedDescription) Your previous shortcut has been kept."
            NSSound.beep()
        }
        recordingAction = nil
    }

    private func reloadShortcuts() {
        shortcuts = CaptureHotkeyPreferences.shortcuts()
    }
}
