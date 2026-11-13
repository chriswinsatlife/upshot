import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotOutputSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotConvertToSRGBKey) private var convertToSRGB = false
    @AppStorage(UpshotPreferences.screenshotScaleToOneXKey) private var scaleToOneX = false
    @AppStorage(UpshotPreferences.screenshotBorderKey) private var border = false
    @AppStorage(UpshotPreferences.screenshotRetinaSuffixKey) private var retinaSuffix = false
    @AppStorage(UpshotPreferences.screenshotShowCursorKey) private var showCursor = false
    @AppStorage(UpshotPreferences.screenshotApplyBackgroundPresetKey) private var applyBackgroundPreset = false
    @AppStorage(UpshotPreferences.screenshotBackgroundPresetIDKey) private var backgroundPresetID = ""
    @State private var presetStore = AnnotationBackgroundPresetStore.shared
    @AppStorage(UpshotPreferences.screenshotWindowBackgroundKey) private var windowBackground = WindowScreenshotBackgroundMode.original.rawValue
    @AppStorage(UpshotPreferences.screenshotWindowWallpaperPathKey) private var windowWallpaperPath = ""
    @AppStorage(UpshotPreferences.screenshotWindowPaddingKey) private var windowPadding = 32.0

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

        Section("Window Screenshot Background") {
            Picker("Background", selection: $windowBackground) {
                ForEach(WindowScreenshotBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            if windowBackground == WindowScreenshotBackgroundMode.customWallpaper.rawValue {
                LabeledContent("Wallpaper") {
                    SettingsButton(windowWallpaperPath.isEmpty ? "Choose Image…" : URL(fileURLWithPath: windowWallpaperPath).lastPathComponent) {
                        let panel = NSOpenPanel()
                        panel.allowedContentTypes = [.image]
                        panel.allowsMultipleSelection = false
                        panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            windowWallpaperPath = url.path
                        }
                    }
                }
            }
            if windowBackground != WindowScreenshotBackgroundMode.original.rawValue {
                Stepper("Padding: \(Int(windowPadding)) pt", value: $windowPadding, in: 0...256, step: 4)
                Text("Transparent padding is preserved in PNG. JPEG exports flatten transparency to white.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
