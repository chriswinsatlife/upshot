import SwiftUI

struct RecordingExportSettingsSection: View {
    @AppStorage("recordingCapturesTypedKeys") private var capturesTypedKeys = false

    var body: some View {
        Section("Keystroke Capture") {
            Toggle("Capture typed keys in future recordings", isOn: $capturesTypedKeys)
                .toggleStyle(.ink)
            Text("Off by default. Typed keys are stored only when this option is enabled. Studio displays command keys by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
