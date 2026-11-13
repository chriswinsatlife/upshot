import SwiftUI

struct SettingsAdvancedPane: View {
    var body: some View {
        InterfaceFormPage {
            CaptureHistorySettingsSection()
            LibraryAnalysisSettingsSection()
            AutomationSettingsSection()
        }
    }
}

struct LibraryAnalysisSettingsSection: View {
    @AppStorage(UpshotPreferences.libraryAnalyzeCapturesKey) private var analyzeCaptures = true
    @AppStorage(UpshotPreferences.librarySortExistingKey) private var sortExistingCaptures = false

    var body: some View {
        InterfaceSection("Library") {
            InterfaceToggleRow(
                "Analyze captures",
                detail: "Text search and categories, processed on this Mac.",
                isOn: $analyzeCaptures
            )

            if analyzeCaptures, CaptureLibraryAnalyzer.isModelAvailable {
                InterfaceToggleRow("Sort existing captures", isOn: $sortExistingCaptures)
                    .transition(.blurPop)
            }
        }
        .motion(value: analyzeCaptures)
        .onChange(of: analyzeCaptures) { _, _ in CaptureLibraryIndex.shared.settingsDidChange() }
        .onChange(of: sortExistingCaptures) { _, _ in CaptureLibraryIndex.shared.settingsDidChange() }
    }
}
