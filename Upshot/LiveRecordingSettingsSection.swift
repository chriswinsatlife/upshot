import SwiftUI

struct LiveRecordingSettingsSection: View {
    @AppStorage(UpshotPreferences.recordingDimOutsideAreaKey) private var dimOutsideArea = true
    @AppStorage(UpshotPreferences.recordingDoNotDisturbKey) private var doNotDisturb = true
    @AppStorage(UpshotPreferences.recordingFocusShortcutNameKey) private var focusShortcutName = "Upshot Recording Focus"

    var body: some View {
        Section("While Recording") {
            Toggle("Dim the screen outside the recorded area", isOn: $dimOutsideArea)
            Toggle("Enable Do Not Disturb", isOn: $doNotDisturb)
            if doNotDisturb {
                TextField("Focus shortcut", text: $focusShortcutName)
                Text("The configured macOS shortcut must save the current Focus, enable Do Not Disturb, and restore the saved Focus after recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
