import SwiftUI

struct SettingsTextRecognitionPane: View {
    var body: some View {
        InterfaceFormPage {
            TextRecognitionSettingsSection()
            TextRecognitionLibrarySection()
        }
    }
}

private struct TextRecognitionLibrarySection: View {
    @AppStorage(UpshotPreferences.libraryAnalyzeCapturesKey) private var analyzeCaptures = true
    @AppStorage(UpshotPreferences.librarySortExistingKey) private var sortExistingCaptures = false

    var body: some View {
        InterfaceSection("Library") {
            InterfaceToggleRow("Analyze captures for search and categories", isOn: $analyzeCaptures)
            if analyzeCaptures, CaptureLibraryAnalyzer.isModelAvailable {
                InterfaceToggleRow(
                    "Sort existing captures",
                    detail: "Uses Apple Intelligence. A large Library can take an hour or more.",
                    isOn: $sortExistingCaptures
                )
                .transition(.blurPop)
            }
        }
        .motion(value: analyzeCaptures)
        .onChange(of: analyzeCaptures) { _, _ in
            AppLog.event("settings", "text_recognition_settings_library_analysis_changed", fields: ["enabled": String(analyzeCaptures)])
            CaptureLibraryIndex.shared.settingsDidChange()
        }
        .onChange(of: sortExistingCaptures) { _, _ in
            AppLog.event("settings", "text_recognition_settings_sort_existing_captures_changed", fields: ["enabled": String(sortExistingCaptures)])
            CaptureLibraryIndex.shared.settingsDidChange()
        }
    }
}
