import SwiftUI

struct ScreenshotsSettingsPane: View {
    var body: some View {
        InterfaceFormPage {
            ScreenshotOutputSettingsSection()
            ScreenshotCaptureSettingsSection()
            WindowScreenshotSettingsSection()
            ScreenshotBackgroundPresetSettingsSection()
            AfterCaptureActionsSection(type: .screenshot, title: "After Capture")
            ScreenshotAnnotationEditorSettingsSection()
        }
    }
}

private struct ScreenshotCaptureSettingsSection: View {
    @AppStorage(UpshotPreferences.captureDelaySecondsKey) private var captureDelaySeconds = 0
    @AppStorage(UpshotPreferences.screenshotShowCursorKey) private var showCursor = false
    @AppStorage(UpshotPreferences.screenshotHideDesktopIconsKey) private var hideDesktopIcons = false
    @AppStorage(UpshotPreferences.trimFullscreenMenuBarKey) private var trimFullscreenMenuBar = true
    @AppStorage(UpshotPreferences.includeAppWindowsInCapturesKey) private var includeAppWindowsInCaptures = false
    @State private var desktopIconsManuallyHidden = false
    @State private var desktopIconError: String?

    private let selfTimerOptions: [Int] = [0, 3, 5, 10]

    var body: some View {
        InterfaceSection("Capture") {
            InterfacePickerRow("Self-timer", selection: $captureDelaySeconds) {
                ForEach(selfTimerOptions, id: \.self) { seconds in
                    Text(seconds == 0 ? "Off" : "\(seconds) seconds").tag(seconds)
                }
            }
            InterfaceToggleRow("Show cursor", isOn: $showCursor)
            AreaSelectionSettingsSection()
            InterfaceToggleRow("Hide desktop icons while capturing", isOn: $hideDesktopIcons)
            InterfaceRow("Desktop icons", detail: desktopIconError, detailIsCritical: desktopIconError != nil) {
                InterfaceActionButton(desktopIconsManuallyHidden ? "Show" : "Hide", action: toggleDesktopIcons)
            }
            InterfaceToggleRow("Trim menu bar from fullscreen captures", isOn: $trimFullscreenMenuBar)
            InterfaceToggleRow("Include floating Upshot UI in captures", isOn: $includeAppWindowsInCaptures)
        }
        .onAppear {
            desktopIconsManuallyHidden = DesktopIconVisibilityService.shared.manuallyHidden
        }
        .onChange(of: includeAppWindowsInCaptures) { _, _ in
            PreviewWindowCaptureExclusion.shared.refreshRegisteredWindows()
        }
    }

    private func toggleDesktopIcons() {
        do {
            try DesktopIconVisibilityService.toggleDesktopIcons()
            desktopIconError = nil
        } catch {
            desktopIconError = error.localizedDescription
        }
        desktopIconsManuallyHidden = DesktopIconVisibilityService.shared.manuallyHidden
    }
}

private struct ScreenshotAnnotationEditorSettingsSection: View {
    @AppStorage(UpshotPreferences.annotationStartingToolKey) private var startingTool = AnnotationTool.select.rawValue
    @AppStorage(UpshotPreferences.lowResolutionEditorPreviewKey) private var lowResolutionEditorPreview = true

    var body: some View {
        InterfaceSection("Annotation Editor") {
            InterfacePickerRow("Starting tool", selection: $startingTool) {
                Text("Last Used").tag(UpshotPreferences.startingToolLastUsed)
                Divider()
                ForEach(AnnotationTool.allCases) { tool in
                    Text(tool.title).tag(tool.rawValue)
                }
            }
            InterfaceToggleRow("Use low-resolution preview to save memory", isOn: $lowResolutionEditorPreview)
            AnnotationEditorSettingsSection()
        }
    }
}
