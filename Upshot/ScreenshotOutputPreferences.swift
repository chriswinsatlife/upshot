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
    static let screenshotHideDesktopIconsKey = "screenshotHideDesktopIcons"
    static let screenshotFilenameTemplateKey = "screenshotFilenameTemplate"
    static let screenshotFilenameCounterKey = "screenshotFilenameCounter"
    static let screenshotAskForNameKey = "screenshotAskForName"
    static let screenshotClipboardModeKey = "screenshotClipboardMode"

    static var screenshotConvertToSRGB: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotConvertToSRGBKey)
    }

    static var screenshotScaleToOneX: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotScaleToOneXKey)
    }

    static var screenshotBorder: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotBorderKey)
    }

    static var screenshotRetinaSuffix: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotRetinaSuffixKey)
    }

    static var screenshotShowCursor: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotShowCursorKey)
    }

    static var screenshotApplyBackgroundPreset: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotApplyBackgroundPresetKey)
    }

    static var screenshotBackgroundPresetID: String {
        UpshotStorage.defaults.string(forKey: screenshotBackgroundPresetIDKey) ?? ""
    }

    static var screenshotWindowBackground: WindowScreenshotBackgroundMode {
        WindowScreenshotBackgroundMode(rawValue: UpshotStorage.defaults.string(forKey: screenshotWindowBackgroundKey) ?? "") ?? .original
    }

    static var screenshotWindowWallpaperPath: String {
        UpshotStorage.defaults.string(forKey: screenshotWindowWallpaperPathKey) ?? ""
    }

    static var screenshotWindowPadding: CGFloat {
        let value = UpshotStorage.defaults.object(forKey: screenshotWindowPaddingKey) as? Double ?? 32
        return value.isFinite ? min(256, max(0, value)) : 32
    }

    static var screenshotHideDesktopIcons: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotHideDesktopIconsKey)
    }

    static var screenshotFilenameTemplate: String {
        UpshotStorage.defaults.string(forKey: screenshotFilenameTemplateKey) ?? ScreenshotFileNaming.defaultTemplate
    }

    static var screenshotAskForName: Bool {
        UpshotStorage.defaults.bool(forKey: screenshotAskForNameKey)
    }

    static var screenshotClipboardMode: ScreenshotClipboardMode {
        ScreenshotClipboardMode(rawValue: UpshotStorage.defaults.string(forKey: screenshotClipboardModeKey) ?? "") ?? .both
    }
}
