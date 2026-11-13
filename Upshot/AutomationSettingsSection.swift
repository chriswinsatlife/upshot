import AppKit
import SwiftUI

struct AutomationSettingsSection: View {
    @State private var reloadFailureMessage: String?

    private var failureMessage: String? {
        reloadFailureMessage ?? AutomationConfiguration.shared.errorMessage
    }

    private var configurationFileName: String {
        UpshotPreferences.configurationFileURL.lastPathComponent
    }

    var body: some View {
        InterfaceSection("Configuration File") {
            InterfaceRow(
                configurationFileName,
                detail: failureMessage,
                detailIsCritical: failureMessage != nil
            ) {
                Button("Reload", action: reloadConfiguration)
                Button("Reveal in Finder", action: revealConfiguration)
            }
            .help(UpshotPreferences.configurationFileURL.abbreviatedPath)
        }
    }

    private func reloadConfiguration() {
        do {
            try AutomationConfiguration.shared.reload()
            reloadFailureMessage = nil
        } catch {
            reloadFailureMessage = error.localizedDescription
            AppLog.event("automation", "configuration_reload_from_settings_failed", fields: ["error": AppLog.error(error)])
        }
    }

    private func revealConfiguration() {
        AutomationConfiguration.shared.synchronize()
        NSWorkspace.shared.activateFileViewerSelecting([UpshotPreferences.configurationFileURL])
        AppLog.event("automation", "configuration_revealed_from_settings")
    }
}
