import SwiftUI

typealias VideoSettingsPane = SettingsScreenRecordingPane

struct SettingsScreenRecordingPane: View {
    @AppStorage(UpshotPreferences.revealExportInFinderKey) private var revealExportInFinder = true

    var body: some View {
        InterfaceFormPage {
            LiveRecordingSettingsSection()

            RecordingExportSettingsSection()

            AfterCaptureActionsSection(type: .recording, title: "After Recording")

            InterfaceSection("Studio") {
                InterfaceToggleRow("Reveal exports in Finder", isOn: $revealExportInFinder)

                InterfaceRow("Recording projects") {
                    InterfaceActionButton("Open Library", systemImage: "square.grid.2x2") {
                        AppLog.event("settings", "recording_projects_library_opened")
                        CaptureLibraryModel.shared.show(filter: .recordings)
                    }
                }
            }
        }
    }
}
