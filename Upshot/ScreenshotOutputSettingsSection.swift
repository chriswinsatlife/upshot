import SwiftUI

struct ScreenshotOutputSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotConvertToSRGBKey) private var convertToSRGB = false
    @AppStorage(UpshotPreferences.screenshotScaleToOneXKey) private var scaleToOneX = false
    @AppStorage(UpshotPreferences.screenshotBorderKey) private var border = false
    @AppStorage(UpshotPreferences.screenshotRetinaSuffixKey) private var retinaSuffix = false
    @AppStorage(UpshotPreferences.screenshotShowCursorKey) private var showCursor = false
    @AppStorage(UpshotPreferences.screenshotApplyBackgroundPresetKey) private var applyBackgroundPreset = false
    @AppStorage(UpshotPreferences.screenshotBackgroundPresetIDKey) private var backgroundPresetID = ""
    @State private var presetStore = AnnotationBackgroundPresetStore.shared

    var body: some View {
        Section("Screenshot Output") {
            Toggle("Convert to sRGB", isOn: $convertToSRGB)
                .toggleStyle(.ink)
            Toggle("Scale Retina screenshots to 1x", isOn: $scaleToOneX)
                .toggleStyle(.ink)
            Toggle("Add a 1px border", isOn: $border)
                .toggleStyle(.ink)
            Toggle("Add @2x to Retina filenames", isOn: $retinaSuffix)
                .toggleStyle(.ink)
            Toggle("Show cursor in screenshots", isOn: $showCursor)
                .toggleStyle(.ink)
        }

        Section("Screenshot Background") {
            Toggle("Apply annotation background preset", isOn: $applyBackgroundPreset)
                .toggleStyle(.ink)
            if applyBackgroundPreset {
                Picker("Preset", selection: $backgroundPresetID) {
                    Text("Active annotation preset").tag("")
                    ForEach(presetStore.presets) { preset in
                        Text(preset.name).tag(preset.id.uuidString)
                            .disabled(preset.hasMissingWallpaper)
                    }
                }
                Text("Hold Shift when taking a screenshot to skip the preset. Create presets in the annotation editor.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
