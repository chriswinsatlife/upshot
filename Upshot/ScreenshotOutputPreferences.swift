import Foundation

extension UpshotPreferences {
    static let screenshotConvertToSRGBKey = "screenshotConvertToSRGB"
    static let screenshotScaleToOneXKey = "screenshotScaleToOneX"
    static let screenshotBorderKey = "screenshotBorder"
    static let screenshotRetinaSuffixKey = "screenshotRetinaSuffix"
    static let screenshotShowCursorKey = "screenshotShowCursor"
    static let screenshotApplyBackgroundPresetKey = "screenshotApplyBackgroundPreset"
    static let screenshotBackgroundPresetIDKey = "screenshotBackgroundPresetID"
    static let screenshotWindowBackgroundKey = "screenshotWindowBackground"
    static let screenshotWindowWallpaperPathKey = "screenshotWindowWallpaperPath"
    static let screenshotWindowPaddingKey = "screenshotWindowPadding"

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

    static var screenshotApplyBackgroundPreset: Bool {
        UserDefaults.standard.bool(forKey: screenshotApplyBackgroundPresetKey)
    }

    static var screenshotBackgroundPresetID: String {
        UserDefaults.standard.string(forKey: screenshotBackgroundPresetIDKey) ?? ""
    }

    static var screenshotWindowBackground: WindowScreenshotBackgroundMode {
        WindowScreenshotBackgroundMode(rawValue: UserDefaults.standard.string(forKey: screenshotWindowBackgroundKey) ?? "") ?? .original
    }

    static var screenshotWindowWallpaperPath: String {
        UserDefaults.standard.string(forKey: screenshotWindowWallpaperPathKey) ?? ""
    }

    static var screenshotWindowPadding: CGFloat {
        let value = UserDefaults.standard.object(forKey: screenshotWindowPaddingKey) as? Double ?? 32
        return value.isFinite ? min(256, max(0, value)) : 32
    }
}
