import Foundation

extension UpshotPreferences {
    static let recordingDimOutsideAreaKey = "recordingDimOutsideArea"

    static var recordingDimOutsideArea: Bool {
        UserDefaults.standard.object(forKey: recordingDimOutsideAreaKey) as? Bool ?? false
    }
}

extension UpshotPreferences {
    static let recordingDoNotDisturbKey = "recordingDoNotDisturb"
    static let recordingFocusShortcutNameKey = "recordingFocusShortcutName"

    static var recordingDoNotDisturb: Bool {
        UserDefaults.standard.object(forKey: recordingDoNotDisturbKey) as? Bool ?? false
    }

    static var recordingFocusShortcutName: String {
        UserDefaults.standard.string(forKey: recordingFocusShortcutNameKey) ?? "Upshot Recording Focus"
    }
}
