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
    @AppStorage(UpshotPreferences.screenshotHideDesktopIconsKey) private var hideDesktopIcons = false
    @State private var desktopIconError: String?
    @AppStorage(UpshotPreferences.screenshotFilenameTemplateKey) private var filenameTemplate = ScreenshotFileNaming.defaultTemplate
    @AppStorage(UpshotPreferences.screenshotFilenameCounterKey) private var filenameCounter = 0
    @AppStorage(UpshotPreferences.screenshotAskForNameKey) private var askForName = false
    @AppStorage(UpshotPreferences.screenshotClipboardModeKey) private var clipboardMode = ScreenshotClipboardMode.both.rawValue

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
            Toggle("Hide desktop icons while capturing", isOn: $hideDesktopIcons)
                .toggleStyle(.ink)
            Picker("Copy to clipboard as", selection: $clipboardMode) {
                ForEach(ScreenshotClipboardMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            InterfaceActionButton("Toggle Desktop Icons") {
                do {
                    try DesktopIconVisibilityService.toggleDesktopIcons()
                    desktopIconError = nil
                } catch {
                    desktopIconError = error.localizedDescription
                }
            }
            if let desktopIconError {
                Text(desktopIconError).font(.caption).foregroundStyle(.red)
            }
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
                    InterfaceActionButton(windowWallpaperPath.isEmpty ? "Choose Image…" : URL(fileURLWithPath: windowWallpaperPath).lastPathComponent) {
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
                Text("Use PNG to preserve transparent padding.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Section("Screenshot Filename") {
            Toggle("Ask for a name after every capture", isOn: $askForName)
                .toggleStyle(.ink)
            TextField("Template", text: $filenameTemplate)
            HStack {
                Text("Insert token")
                Spacer()
                Menu("Tokens") {
                    ForEach(ScreenshotFileNaming.tokens, id: \.self) { token in
                        Button(token) { filenameTemplate.append(token) }
                    }
                }
                .fixedSize()
            }
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                LabeledContent("Preview") {
                    Text(ScreenshotFileNaming.captureFileName(
                        date: timeline.date,
                        appName: "Safari",
                        captureType: .window,
                        outputScale: scaleToOneX ? 1 : 2,
                        template: filenameTemplate,
                        counter: filenameCounter < Int.max ? max(0, filenameCounter) + 1 : 1
                    ))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .lineLimit(3)
                }
            }
            if let error = ScreenshotFileNaming.templateError(filenameTemplate) {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Text("{date}: local date · {time}: local time · {app}: app name · {type}: capture type · {counter}: capture number")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
