import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotOutputSettingsSection: View {
    @AppStorage(UpshotPreferences.autoCompressKey) private var autoCompress = false
    @AppStorage(UpshotPreferences.exportFormatKey) private var exportFormatRawValue = ""
    @AppStorage(UpshotPreferences.compressionQualityKey) private var compressionQuality = 0.8
    @AppStorage(UpshotPreferences.screenshotClipboardModeKey) private var clipboardMode = ScreenshotClipboardMode.both.rawValue
    @AppStorage(UpshotPreferences.screenshotConvertToSRGBKey) private var convertToSRGB = false
    @AppStorage(UpshotPreferences.screenshotScaleToOneXKey) private var scaleToOneX = false
    @AppStorage(UpshotPreferences.screenshotBorderKey) private var border = false
    @AppStorage(UpshotPreferences.screenshotRetinaSuffixKey) private var retinaSuffix = false
    @AppStorage(UpshotPreferences.screenshotAskForNameKey) private var askForName = false

    private var exportFormat: Binding<ScreenshotExportFormat> {
        Binding(
            get: { ScreenshotExportFormat(rawValue: exportFormatRawValue) ?? (autoCompress ? .jpeg : .png) },
            set: { format in
                exportFormatRawValue = format.rawValue
                autoCompress = format.usesLossyQuality
            }
        )
    }

    private var steppedQuality: Binding<Double> {
        Binding(
            get: { compressionQuality },
            set: { compressionQuality = ($0 / 0.05).rounded() * 0.05 }
        )
    }

    var body: some View {
        InterfaceSection("Output") {
            InterfacePickerRow("File format", selection: exportFormat) {
                ForEach(ScreenshotExportFormat.allCases) { format in
                    Text(format.title).tag(format)
                }
            }
            if exportFormat.wrappedValue.usesLossyQuality {
                InterfaceRow("Quality") {
                    Slider(value: steppedQuality, in: 0.1...1)
                        .controlSize(.small)
                        .frame(width: 160)
                        .accessibilityLabel("Quality")
                        .accessibilityValue(compressionQuality.formatted(.percent.precision(.fractionLength(0))))
                    InterfaceValueWithUnitLabel(value: "\(Int((compressionQuality * 100).rounded()))", unit: "%", unitSpacing: .none)
                }
            }
            InterfacePickerRow("Copy to clipboard as", selection: $clipboardMode) {
                ForEach(ScreenshotClipboardMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
        }

        InterfaceSection(nil) {
            InterfaceToggleRow("Convert to sRGB profile", isOn: $convertToSRGB)
            InterfaceToggleRow("Scale Retina screenshots to 1x", isOn: $scaleToOneX)
            InterfaceToggleRow("Add 1px border", isOn: $border)
        }

        InterfaceSection(nil) {
            ScreenshotFileNameTemplateRow(scaleToOneX: scaleToOneX)
            InterfaceToggleRow("Add @2x to Retina file names", isOn: $retinaSuffix)
            InterfaceToggleRow("Ask for a name after every capture", isOn: $askForName)
        }
    }
}

private struct ScreenshotFileNameTemplateRow: View {
    let scaleToOneX: Bool

    @AppStorage(UpshotPreferences.screenshotFilenameTemplateKey) private var filenameTemplate = ScreenshotFileNaming.defaultTemplate
    @AppStorage(UpshotPreferences.screenshotFilenameCounterKey) private var filenameCounter = 0

    private let tokenTitles: [String: String] = [
        "{date}": "Date",
        "{time}": "Time",
        "{app}": "App Name",
        "{type}": "Capture Type",
        "{counter}": "Capture Number"
    ]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let templateError = ScreenshotFileNaming.templateError(filenameTemplate)
            InterfaceRow(
                "File name",
                detail: templateError ?? previewFileName(date: timeline.date),
                detailIsCritical: templateError != nil
            ) {
                TextField("", text: $filenameTemplate, prompt: Text(ScreenshotFileNaming.defaultTemplate))
                    .labelsHidden()
                    .font(.dsBody)
                    .interfaceFieldChrome()
                    .frame(width: 200)
                    .accessibilityLabel("File name template")
                Menu {
                    ForEach(ScreenshotFileNaming.tokens, id: \.self) { token in
                        Button {
                            filenameTemplate.append(token)
                        } label: {
                            Text(tokenTitles[token] ?? token)
                            Text(token)
                        }
                    }
                } label: {
                    Text("Insert")
                }
                .menuStyle(.button)
                .buttonStyle(.interfaceAction)
                .fixedSize()
                .accessibilityLabel("Insert file name token")
            }
        }
    }

    private func previewFileName(date: Date) -> String {
        ScreenshotFileNaming.captureFileName(
            date: date,
            appName: "Safari",
            captureType: .window,
            outputScale: scaleToOneX ? 1 : 2,
            template: filenameTemplate,
            counter: filenameCounter < Int.max ? max(0, filenameCounter) + 1 : 1
        )
    }
}

struct WindowScreenshotSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotWindowBackgroundKey) private var windowBackground = WindowScreenshotBackgroundMode.original.rawValue
    @AppStorage(UpshotPreferences.screenshotWindowWallpaperPathKey) private var windowWallpaperPath = ""
    @AppStorage(UpshotPreferences.screenshotWindowPaddingKey) private var windowPadding = 32.0
    @AppStorage(UpshotPreferences.captureWindowShadowKey) private var captureWindowShadow = false
    @AppStorage(UpshotPreferences.exportFormatKey) private var exportFormatRawValue = ""
    @AppStorage(UpshotPreferences.autoCompressKey) private var autoCompress = false

    private var backgroundMode: WindowScreenshotBackgroundMode {
        WindowScreenshotBackgroundMode(rawValue: windowBackground) ?? .original
    }

    private var exportFormat: ScreenshotExportFormat {
        ScreenshotExportFormat(rawValue: exportFormatRawValue) ?? (autoCompress ? .jpeg : .png)
    }

    private var steppedPadding: Binding<Double> {
        Binding(
            get: { windowPadding },
            set: { windowPadding = ($0 / 4).rounded() * 4 }
        )
    }

    var body: some View {
        InterfaceSection("Window Screenshots") {
            InterfacePickerRow(
                "Background",
                detail: backgroundMode == .transparent && exportFormat != .png ? "Transparent padding needs the PNG format." : nil,
                selection: $windowBackground
            ) {
                ForEach(WindowScreenshotBackgroundMode.allCases) { mode in
                    Text(mode.title).tag(mode.rawValue)
                }
            }
            if backgroundMode == .customWallpaper {
                InterfaceRow("Wallpaper") {
                    if !windowWallpaperPath.isEmpty {
                        Text(URL(fileURLWithPath: windowWallpaperPath).lastPathComponent)
                            .font(.dsBody)
                            .foregroundStyle(Palette.secondaryLabel)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(windowWallpaperPath)
                    }
                    Button("Choose…", action: chooseWallpaper)
                }
            }
            if backgroundMode != .original {
                InterfaceRow("Padding") {
                    Slider(value: steppedPadding, in: 0...256)
                        .controlSize(.small)
                        .frame(width: 160)
                        .accessibilityLabel("Padding")
                        .accessibilityValue("\(Int(windowPadding)) points")
                    InterfaceValueWithUnitLabel(value: "\(Int(windowPadding))", unit: "pt")
                }
            }
            InterfaceToggleRow("Capture window shadow", isOn: $captureWindowShadow)
        }
    }

    private func chooseWallpaper() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            windowWallpaperPath = url.path
        }
    }
}

struct ScreenshotBackgroundPresetSettingsSection: View {
    @AppStorage(UpshotPreferences.screenshotApplyBackgroundPresetKey) private var applyBackgroundPreset = false
    @AppStorage(UpshotPreferences.screenshotBackgroundPresetIDKey) private var backgroundPresetID = ""
    @State private var presetStore = AnnotationBackgroundPresetStore.shared

    private var presetSelection: Binding<String?> {
        Binding(
            get: { applyBackgroundPreset ? backgroundPresetID : nil },
            set: { selection in
                if let selection {
                    backgroundPresetID = selection
                    applyBackgroundPreset = true
                } else {
                    applyBackgroundPreset = false
                }
            }
        )
    }

    var body: some View {
        InterfaceSection("Background Preset") {
            InterfacePickerRow(
                "Apply to screenshots",
                detail: applyBackgroundPreset ? "Hold Shift while capturing to skip the preset." : nil,
                selection: presetSelection
            ) {
                Text("None").tag(String?.none)
                Divider()
                Text("Active annotation preset").tag(String?.some(""))
                ForEach(presetStore.presets) { preset in
                    Text(preset.name).tag(String?.some(preset.id.uuidString))
                        .disabled(preset.hasMissingWallpaper)
                }
            }
        }
    }
}
