import SwiftUI
import Vision

struct TextRecognitionSettingsSection: View {
    @AppStorage(UpshotPreferences.recognitionLanguageKey) private var language = ""
    @AppStorage(UpshotPreferences.recognitionKeepLineBreaksKey) private var keepLineBreaks = true
    @AppStorage(UpshotPreferences.recognitionDetectLinksKey) private var detectLinks = true
    @State private var languages: [String] = []
    @State private var languageError: String?

    var body: some View {
        Section("Text Recognition") {
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
                SettingsControlLabel("Detect links", detail: "Offer to open links found in recognized text and QR codes or barcodes.")
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
                NSLog("Text recognition settings language loading failed: %@", String(describing: error))
            }
        }
        .onChange(of: language) { _, _ in NSLog("Text recognition settings language changed: %@", language.isEmpty ? "automatic" : language) }
        .onChange(of: keepLineBreaks) { _, _ in NSLog("Text recognition settings keep line breaks changed: %@", keepLineBreaks.description) }
        .onChange(of: detectLinks) { _, _ in NSLog("Text recognition settings detect links changed: %@", detectLinks.description) }
    }
}
