import Foundation

extension UpshotPreferences {
    static let screenshotConvertToSRGBKey = "screenshotConvertToSRGB"
    static let screenshotScaleToOneXKey = "screenshotScaleToOneX"
    static let screenshotBorderKey = "screenshotBorder"
    static let screenshotRetinaSuffixKey = "screenshotRetinaSuffix"
    static let screenshotShowCursorKey = "screenshotShowCursor"

    static var screenshotConvertToSRGB: Bool {
        UserDefaults.standard.bool(forKey: screenshotConvertToSRGBKey)
    }

    static var screenshotScaleToOneX: Bool {
        UserDefaults.standard.bool(forKey: screenshotScaleToOneXKey)
    }

    static var screenshotBorder: Bool {
        UserDefaults.standard.bool(forKey: screenshotBorderKey)
    }

    static var screenshotRetinaSuffix: Bool {
        UserDefaults.standard.bool(forKey: screenshotRetinaSuffixKey)
    }

    static var screenshotShowCursor: Bool {
        UserDefaults.standard.bool(forKey: screenshotShowCursorKey)
    }
}
