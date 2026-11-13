import Foundation

enum AfterCaptureType: String {
    case screenshot
    case recording
}

enum AfterCaptureAction: String, CaseIterable, Identifiable {
    case showOverlay
    case copy
    case save
    case upload
    case annotate
    case pin
    case openVideoEditor

    var id: String { rawValue }

    var title: String {
        switch self {
        case .showOverlay: "Show preview overlay"
        case .copy: "Copy to clipboard"
        case .save: "Save to folder"
        case .upload: "Upload to Cloud & copy link"
        case .annotate: "Open annotation editor"
        case .pin: "Pin to screen"
        case .openVideoEditor: "Open recording editor"
        }
    }

    var subtitle: String {
        switch self {
        case .showOverlay: "Show the floating preview card after capturing."
        case .copy: "Copy the capture to the clipboard."
        case .save: "Automatically save the capture to the export folder."
        case .upload: "Upload to your cloud and copy the share link."
        case .annotate: "Jump straight into the annotation editor."
        case .pin: "Pin the screenshot on top of everything for reference."
        case .openVideoEditor: "Edit the clip, background, camera, audio, and zooms in one place."
        }
    }

    static func actions(for type: AfterCaptureType) -> [AfterCaptureAction] {
        switch type {
        case .screenshot:
            [.showOverlay, .copy, .save, .upload, .annotate, .pin]
        case .recording:
            [.showOverlay, .copy, .save, .upload, .openVideoEditor]
        }
    }

    func storageKey(for type: AfterCaptureType) -> String {
        switch (self, type) {
        case (.copy, .screenshot):
            return UpshotPreferences.autoCopyKey
        case (.save, .screenshot):
            return UpshotPreferences.autoSaveKey
        default:
            return "afterCapture.\(type.rawValue).\(rawValue)"
        }
    }

    var defaultValue: Bool {
        self == .showOverlay || self == .openVideoEditor
    }
}

enum AfterCaptureActions {
    static func copyScreenshotToClipboard(from url: URL) throws {
        try ScreenshotClipboardService.copy(from: url)
    }

    static func isEnabled(_ action: AfterCaptureAction, for type: AfterCaptureType) -> Bool {
        let key = action.storageKey(for: type)
        if UpshotStorage.defaults.object(forKey: key) == nil {
            return action.defaultValue
        }
        return UpshotStorage.defaults.bool(forKey: key)
    }
}
