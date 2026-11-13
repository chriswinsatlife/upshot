import AppKit
import SwiftUI

struct AutomationSettingsSection: View {
    @State private var errorMessage: String?

    var body: some View {
        Section("Configuration File") {
            Text("Preferences and shortcuts synchronize with ~/.config/upshot/config.toml.")
                .foregroundStyle(.secondary)
            HStack {
                SettingsButton("Reveal Configuration") {
                    AutomationConfiguration.shared.synchronize()
                    NSWorkspace.shared.activateFileViewerSelecting([UpshotPreferences.configurationFileURL])
                }
                SettingsButton("Reload Configuration") {
                    do {
                        try AutomationConfiguration.shared.reload()
                        errorMessage = nil
                    } catch { errorMessage = error.localizedDescription }
                }
            }
            if let message = errorMessage ?? AutomationConfiguration.shared.errorMessage {
                Text(message).font(.caption).foregroundStyle(Palette.record)
            }
        }
    }
}
