import Foundation

extension UpshotPreferences {
    static let screenshotConvertToSRGBKey = "screenshotConvertToSRGB"

    static var screenshotConvertToSRGB: Bool {
        UserDefaults.standard.bool(forKey: screenshotConvertToSRGBKey)
    }
}
