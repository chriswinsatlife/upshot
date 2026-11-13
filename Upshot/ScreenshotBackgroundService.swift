import CoreGraphics
import Foundation

enum ScreenshotBackgroundService {
    static func presetSettings(skipPreset: Bool) throws -> AnnotationBackgroundSettings? {
        guard UpshotPreferences.screenshotApplyBackgroundPreset else { return nil }
        guard !skipPreset else {
            AppLog.event("capture", "screenshot_output_background_preset_skipped_with_shift")
            return nil
        }
        let store = AnnotationBackgroundPresetStore.shared
        let selectedID = UUID(uuidString: UpshotPreferences.screenshotBackgroundPresetID)
        guard let preset = selectedID.flatMap({ store.preset(id: $0) }) ?? (selectedID == nil ? store.activePreset : nil),
              !preset.hasMissingWallpaper else {
            throw ScreenshotBackgroundError.presetUnavailable
        }
        AppLog.event("capture", "screenshot_output_background_preset_selected", fields: ["id": String(describing: preset.id.uuidString)])
        return preset.settings
    }

    nonisolated static func applyPreset(
        to image: CGImage,
        settings: AnnotationBackgroundSettings
    ) throws -> CGImage {
        let lease = AnnotationBackgroundRenderer.beginWallpaperUse()
        defer { withExtendedLifetime(lease) {} }
        let output = try AnnotationBackgroundRenderer.compose(
            contentImage: image,
            settings: settings,
            colorSpace: ScreenshotPixelProcessor.colorSpace(for: image),
            canvasOverlay: { context, layout, _ in
                AnnotationBackgroundRenderer.drawWatermark(
                    settings.watermark,
                    in: CGRect(origin: .zero, size: layout.canvasSize),
                    context: context
                )
            }
        )
        AppLog.event("capture", "screenshot_output_background_preset_applied", fields: ["height": String(describing: output.height), "width": String(describing: output.width)])
        return output
    }
}

enum ScreenshotBackgroundError: LocalizedError {
    case presetUnavailable

    var errorDescription: String? {
        switch self {
        case .presetUnavailable: "The screenshot background preset is unavailable. Select a preset in Screenshot Output settings."
        }
    }
}
