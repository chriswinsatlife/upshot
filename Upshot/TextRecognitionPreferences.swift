import Foundation

extension UpshotPreferences {
    static let recognitionDetectCodesKey = "recognitionDetectCodes"

    static var recognitionDetectCodes: Bool {
        UpshotStorage.defaults.bool(forKey: recognitionDetectCodesKey)
    }

    static let recognitionLanguageKey = "recognitionLanguage"
    static let recognitionKeepLineBreaksKey = "recognitionKeepLineBreaks"
    static let recognitionDetectLinksKey = "recognitionDetectLinks"

    static var recognitionLanguage: String {
        UpshotStorage.defaults.string(forKey: recognitionLanguageKey) ?? ""
    }

    static var recognitionKeepLineBreaks: Bool {
        UpshotStorage.defaults.object(forKey: recognitionKeepLineBreaksKey) as? Bool ?? true
    }

    static var recognitionDetectLinks: Bool {
        UpshotStorage.defaults.object(forKey: recognitionDetectLinksKey) as? Bool ?? true
    }
}

nonisolated struct TextRecognitionOptions: Sendable {
    let language: String
    let keepLineBreaks: Bool
    let detectLinks: Bool

    @MainActor
    static var current: Self {
        Self(language: UpshotPreferences.recognitionLanguage,
             keepLineBreaks: UpshotPreferences.recognitionKeepLineBreaks,
             detectLinks: UpshotPreferences.recognitionDetectLinks)
    }
}
