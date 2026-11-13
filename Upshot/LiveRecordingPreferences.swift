import Foundation

extension UpshotPreferences {
    static let recordingDimOutsideAreaKey = "recordingDimOutsideArea"

    static var recordingDimOutsideArea: Bool {
        UpshotStorage.defaults.object(forKey: recordingDimOutsideAreaKey) as? Bool ?? false
    }
}

extension UpshotPreferences {
    static let recordingDoNotDisturbKey = "recordingDoNotDisturb"
    static let recordingFocusShortcutNameKey = "recordingFocusShortcutName"

    static var recordingDoNotDisturb: Bool {
        UpshotStorage.defaults.object(forKey: recordingDoNotDisturbKey) as? Bool ?? false
    }

    static var recordingFocusShortcutName: String {
        UpshotStorage.defaults.string(forKey: recordingFocusShortcutNameKey) ?? "Upshot Recording Focus"
    }
}
