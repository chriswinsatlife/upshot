import Foundation

extension UpshotPreferences {
    static let previewMoveToActiveScreenKey = "previewMoveToActiveScreen"

    static var previewMoveToActiveScreen: Bool {
        UpshotStorage.defaults.bool(forKey: previewMoveToActiveScreenKey)
    }
}
