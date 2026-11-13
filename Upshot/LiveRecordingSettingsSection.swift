import SwiftUI

struct LiveRecordingSettingsSection: View {
    @AppStorage(UpshotPreferences.recordingDimOutsideAreaKey) private var dimOutsideArea = false
    @AppStorage(UpshotPreferences.recordingDoNotDisturbKey) private var doNotDisturb = false
    @AppStorage(UpshotPreferences.recordingFocusShortcutNameKey) private var focusShortcutName = "Upshot Recording Focus"

    var body: some View {
        Section("While Recording") {
            Toggle("Dim the screen outside the recorded area", isOn: $dimOutsideArea)
                .toggleStyle(.ink)
            Toggle("Enable Do Not Disturb", isOn: $doNotDisturb)
                .toggleStyle(.ink)
            if doNotDisturb {
                TextField("Focus shortcut", text: $focusShortcutName)
                Text("The configured macOS shortcut must save the current Focus, enable Do Not Disturb, and restore the saved Focus after recording.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
