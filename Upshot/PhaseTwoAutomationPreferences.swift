import Foundation

extension AutomationPreferenceDefinition {
    static var phaseTwoCatalog: [String: Self] {
        var values: [String: Self] = [:]
        let booleans: [String: Bool] = [
            UpshotPreferences.areaSelectionFreezeScreenKey: true,
            UpshotPreferences.areaSelectionCrosshairKey: true,
            UpshotPreferences.areaSelectionMagnifierKey: true,
            UpshotPreferences.screenshotConvertToSRGBKey: false,
            UpshotPreferences.screenshotScaleToOneXKey: false,
            UpshotPreferences.screenshotBorderKey: false,
            UpshotPreferences.screenshotRetinaSuffixKey: false,
            UpshotPreferences.screenshotShowCursorKey: false,
            UpshotPreferences.screenshotApplyBackgroundPresetKey: false,
            UpshotPreferences.screenshotHideDesktopIconsKey: false,
            UpshotPreferences.screenshotAskForNameKey: false,
            UpshotPreferences.recognitionDetectCodesKey: false,
            UpshotPreferences.recognitionKeepLineBreaksKey: true,
            UpshotPreferences.recognitionDetectLinksKey: true,
            UpshotPreferences.annotationEditorAlwaysOnTopKey: false,
            UpshotPreferences.annotationObjectShadowsKey: false,
            UpshotPreferences.annotationAutomaticallyExpandCanvasKey: false,
            UpshotPreferences.previewCloseAfterUploadingKey: false,
            UpshotPreferences.pinnedScreenshotRoundedCornersKey: true,
            UpshotPreferences.pinnedScreenshotShadowKey: true,
            UpshotPreferences.pinnedScreenshotBorderKey: true,
            UpshotPreferences.recordingDimOutsideAreaKey: false,
            UpshotPreferences.recordingDoNotDisturbKey: false,
            "recordingCapturesTypedKeys": false
        ]
        for (key, value) in booleans { values[key] = Self(defaultValue: .bool(value)) }
        values[UpshotPreferences.allInOneLastModeKey] = Self(defaultValue: "area", choices: AllInOneCaptureMode.allCases.map(\.rawValue))
        for key in [UpshotPreferences.allInOneLastSelectionRectKey, UpshotPreferences.areaSelectionLastScreenshotRectKey] {
            values[key] = Self(defaultValue: .array([]), arrayKind: .rectangle)
        }
        for key in [UpshotPreferences.allInOneLastSelectionDisplaysKey, UpshotPreferences.areaSelectionLastScreenshotDisplaysKey] {
            values[key] = Self(defaultValue: .array([]), arrayKind: .strings)
        }
        values[UpshotPreferences.screenshotBackgroundPresetIDKey] = Self(defaultValue: "")
        values[UpshotPreferences.screenshotWindowBackgroundKey] = Self(defaultValue: "original", choices: WindowScreenshotBackgroundMode.allCases.map(\.rawValue))
        values[UpshotPreferences.screenshotWindowWallpaperPathKey] = Self(defaultValue: "")
        values[UpshotPreferences.screenshotWindowPaddingKey] = Self(defaultValue: 32, range: 0...256)
        values[UpshotPreferences.screenshotFilenameTemplateKey] = Self(defaultValue: .string(ScreenshotFileNaming.defaultTemplate))
        values[UpshotPreferences.screenshotFilenameCounterKey] = Self(defaultValue: 0, range: 0...Double(Int.max), integral: true)
        values[UpshotPreferences.screenshotClipboardModeKey] = Self(defaultValue: "both", choices: ScreenshotClipboardMode.allCases.map(\.rawValue))
        values[UpshotPreferences.recognitionLanguageKey] = Self(defaultValue: "")
        values[UpshotPreferences.annotationDrawingSmoothingKey] = Self(defaultValue: 0.62, range: 0...1)
        values[UpshotPreferences.previewOverlaySizeKey] = Self(defaultValue: "small", choices: QuickAccessOverlaySize.allCases.map(\.rawValue))
        values[UpshotPreferences.previewAutoCloseActionKey] = Self(defaultValue: "close", choices: QuickAccessAutoCloseAction.allCases.map(\.rawValue))
        values[UpshotPreferences.previewSwipeTowardEdgeActionKey] = Self(defaultValue: "tuck", choices: QuickAccessSwipeAction.allCases.map(\.rawValue))
        values[UpshotPreferences.previewSwipeAwayFromEdgeActionKey] = Self(defaultValue: "none", choices: QuickAccessSwipeAction.allCases.map(\.rawValue))
        values[UpshotPreferences.historyRetentionDaysKey] = Self(defaultValue: 0, range: 0...Double(Int.max), integral: true)
        values[UpshotPreferences.recordingFocusShortcutNameKey] = Self(defaultValue: "Upshot Recording Focus")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let delivery = String(decoding: try! encoder.encode(RecordingExportDeliveryOptions()), as: UTF8.self)
        values["recordingExtendedExportDefaults"] = Self(defaultValue: .string(delivery), storesJSONData: true)
        return values
    }
}
