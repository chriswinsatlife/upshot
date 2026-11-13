import Foundation

extension UpshotPreferences {
    static let recordingDimOutsideAreaKey = "recordingDimOutsideArea"

    static var recordingDimOutsideArea: Bool {
        UserDefaults.standard.object(forKey: recordingDimOutsideAreaKey) as? Bool ?? true
    }
}
