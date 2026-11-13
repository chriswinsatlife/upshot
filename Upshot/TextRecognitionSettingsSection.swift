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
        Section("Text Recognition") {
            Toggle("Detect QR codes and barcodes after capture", isOn: $detectCodes)
                .toggleStyle(.ink)
            Picker("Recognition language", selection: $language) {
                Text("Automatic").tag("")
                ForEach(languages, id: \.self) { identifier in
                    Text(Locale.current.localizedString(forIdentifier: identifier) ?? identifier).tag(identifier)
                }
                if !language.isEmpty, !languages.contains(language) {
                    Text("\(language) — unavailable").tag(language)
                }
            }
            if let languageError {
                Text(languageError).font(.caption).foregroundStyle(.secondary)
            }
            Toggle("Keep line breaks", isOn: $keepLineBreaks)
                .toggleStyle(.ink)
            Toggle(isOn: $detectLinks) {
                InterfaceRowLabel("Detect links", detail: "Offer to open links found in recognized text and QR codes or barcodes.")
            }
            .toggleStyle(.ink)
        }
        .task {
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                languages = try request.supportedRecognitionLanguages().sorted {
                    (Locale.current.localizedString(forIdentifier: $0) ?? $0)
                        .localizedStandardCompare(Locale.current.localizedString(forIdentifier: $1) ?? $1) == .orderedAscending
                }
            } catch {
                languageError = "Recognition languages could not be loaded."
                AppLog.event("settings", "text_recognition_settings_language_loading_failed", fields: ["error": AppLog.error(error)])
            }
        }
        .onChange(of: language) { _, _ in AppLog.event("settings", "text_recognition_settings_language_changed", fields: ["language": String(describing: language.isEmpty ? "automatic" : language)]) }
        .onChange(of: keepLineBreaks) { _, _ in AppLog.event("settings", "text_recognition_settings_keep_line_breaks_changed", fields: ["enabled": String(keepLineBreaks)]) }
        .onChange(of: detectLinks) { _, _ in AppLog.event("settings", "text_recognition_settings_detect_links_changed", fields: ["enabled": String(detectLinks)]) }
    }
}
