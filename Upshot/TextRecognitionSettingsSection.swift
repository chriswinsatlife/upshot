import SwiftUI
import Vision

struct TextRecognitionSettingsSection: View {
    @AppStorage(UpshotPreferences.recognitionLanguageKey) private var language = ""
    @AppStorage(UpshotPreferences.recognitionKeepLineBreaksKey) private var keepLineBreaks = true
    @AppStorage(UpshotPreferences.recognitionDetectLinksKey) private var detectLinks = true
    @AppStorage(UpshotPreferences.recognitionDetectCodesKey) private var detectCodes = false
    @State private var languages: [String] = []
    @State private var languageError: String?

    var body: some View {
        InterfaceSection("Text") {
            InterfacePickerRow("Language", detail: languageError, selection: $language) {
                Text("Automatic").tag("")
                Divider()
                ForEach(languages, id: \.self) { identifier in
                    Text(Self.displayName(for: identifier)).tag(identifier)
                }
                if !language.isEmpty, !languages.contains(language) {
                    Text("\(language) (Unavailable)").tag(language)
                }
            }
            InterfaceToggleRow("Keep line breaks", isOn: $keepLineBreaks)
            InterfaceToggleRow("Detect links", isOn: $detectLinks)
        }
        .task { loadLanguages() }
        .onChange(of: language) { _, _ in AppLog.event("settings", "text_recognition_settings_language_changed", fields: ["language": String(describing: language.isEmpty ? "automatic" : language)]) }
        .onChange(of: keepLineBreaks) { _, _ in AppLog.event("settings", "text_recognition_settings_keep_line_breaks_changed", fields: ["enabled": String(keepLineBreaks)]) }
        .onChange(of: detectLinks) { _, _ in AppLog.event("settings", "text_recognition_settings_detect_links_changed", fields: ["enabled": String(detectLinks)]) }

        InterfaceSection("Codes") {
            InterfaceToggleRow("Detect QR codes and barcodes after capture", isOn: $detectCodes)
        }
        .onChange(of: detectCodes) { _, _ in AppLog.event("settings", "text_recognition_settings_detect_codes_changed", fields: ["enabled": String(detectCodes)]) }
    }

    private func loadLanguages() {
        do {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            languages = try request.supportedRecognitionLanguages().sorted {
                Self.displayName(for: $0).localizedStandardCompare(Self.displayName(for: $1)) == .orderedAscending
            }
        } catch {
            languageError = "Languages could not be loaded."
            AppLog.event("settings", "text_recognition_settings_language_loading_failed", fields: ["error": AppLog.error(error)])
        }
    }

    private static func displayName(for identifier: String) -> String {
        Locale.current.localizedString(forIdentifier: identifier) ?? identifier
    }
}
