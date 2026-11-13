import SwiftUI

struct LiveRecordingSettingsSection: View {
    @AppStorage(UpshotPreferences.recordingDimOutsideAreaKey) private var dimOutsideArea = false
    @AppStorage(UpshotPreferences.recordingStartDelaySecondsKey) private var countdownSeconds = 0
    @AppStorage(UpshotPreferences.recordingDoNotDisturbKey) private var doNotDisturb = false
    @AppStorage(UpshotPreferences.recordingFocusShortcutNameKey) private var focusShortcutName = "Upshot Recording Focus"
    @AppStorage("recordingCapturesTypedKeys") private var capturesTypedKeys = false

    private static let countdownOptions = [0, 1, 3, 5]

    var body: some View {
        InterfaceSection("General") {
            InterfaceToggleRow("Dim screen while recording", isOn: $dimOutsideArea)

            InterfacePickerRow("Countdown", selection: $countdownSeconds) {
                ForEach(countdownChoices, id: \.self) { seconds in
                    Text(Self.countdownTitle(seconds)).tag(seconds)
                }
            }

            InterfaceToggleRow("\u{201C}Do Not Disturb\u{201D} while recording", isOn: $doNotDisturb)

            if doNotDisturb {
                InterfaceTextFieldRow(
                    "Focus shortcut",
                    detail: "A Shortcuts shortcut that turns on Do Not Disturb and restores Focus.",
                    prompt: "Upshot Recording Focus",
                    text: $focusShortcutName
                )
            }
        }

        InterfaceSection("Keystrokes") {
            InterfaceToggleRow("Record typed keys", detail: "Shortcuts are always recorded.", isOn: $capturesTypedKeys)
        }
    }

    private var countdownChoices: [Int] {
        Self.countdownOptions.contains(countdownSeconds)
            ? Self.countdownOptions
            : (Self.countdownOptions + [countdownSeconds]).sorted()
    }

    private static func countdownTitle(_ seconds: Int) -> String {
        seconds == 0 ? "None" : "\(seconds) second\(seconds == 1 ? "" : "s")"
    }
}
