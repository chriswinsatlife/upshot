import AppKit
import SwiftUI

struct SettingsQuickAccessPane: View {
    @AppStorage(UpshotPreferences.previewPositionKey) private var positionRaw = PreviewOverlayPosition.right.rawValue
    @AppStorage(UpshotPreferences.previewMoveToActiveScreenKey) private var moveToActiveScreen = false
    @AppStorage(UpshotPreferences.previewOverlaySizeKey) private var overlaySize = QuickAccessOverlaySize.small
    @AppStorage(UpshotPreferences.previewAutoCloseSecondsKey) private var autoCloseSeconds = 0
    @AppStorage(UpshotPreferences.previewAutoCloseActionKey) private var autoCloseAction = QuickAccessAutoCloseAction.close
    @AppStorage(UpshotPreferences.previewCloseAfterDraggingKey) private var closeAfterDragging = true
    @AppStorage(UpshotPreferences.previewCloseAfterUploadingKey) private var closeAfterUploading = false
    @AppStorage(UpshotPreferences.saveButtonUsesFolderKey) private var saveButtonUsesFolder = false
    @AppStorage(UpshotPreferences.previewSwipeTowardEdgeActionKey) private var swipeTowardEdgeAction = QuickAccessSwipeAction.tuck
    @AppStorage(UpshotPreferences.previewSwipeAwayFromEdgeActionKey) private var swipeAwayFromEdgeAction = QuickAccessSwipeAction.none
    @AppStorage(UpshotPreferences.pinnedScreenshotRoundedCornersKey) private var pinnedRoundedCorners = true
    @AppStorage(UpshotPreferences.pinnedScreenshotShadowKey) private var pinnedShadow = true
    @AppStorage(UpshotPreferences.pinnedScreenshotBorderKey) private var pinnedBorder = true
    @State private var accessibilityGranted: Bool
    @State private var lastAutoCloseInterval = Self.defaultAutoCloseInterval

    private static let defaultAutoCloseInterval = 10
    private static let autoCloseIntervals = [5, 10, 30, 60]

    init(accessibilityGranted: Bool? = nil) {
        _accessibilityGranted = State(initialValue: accessibilityGranted ?? CaptureShelfKeyboardShortcuts.accessibilityGranted)
    }

    var body: some View {
        InterfaceFormPage {
            InterfaceSection("Appearance") {
                InterfaceRow("Position on screen") {
                    InterfaceModeSwitch("Position on screen", selection: positionBinding, options: [
                        InterfaceModeSwitchOption(value: PreviewOverlayPosition.left, title: "Left"),
                        InterfaceModeSwitchOption(value: PreviewOverlayPosition.right, title: "Right")
                    ])
                }
                InterfaceToggleRow("Move to active screen", isOn: $moveToActiveScreen)
                InterfaceRow("Overlay size") {
                    InterfaceModeSwitch("Overlay size", selection: $overlaySize, options: QuickAccessOverlaySize.allCases.map {
                        InterfaceModeSwitchOption(value: $0, title: $0.title)
                    })
                }
            }

            InterfaceSection("Behavior") {
                InterfaceToggleRow("Auto-close", isOn: autoCloseEnabledBinding)
                if autoCloseSeconds > 0 {
                    InterfacePickerRow("Action", selection: $autoCloseAction) {
                        ForEach(QuickAccessAutoCloseAction.allCases) { action in
                            Text(action.title).tag(action)
                        }
                    }
                    InterfacePickerRow("Interval", selection: $autoCloseSeconds) {
                        ForEach(autoCloseIntervalChoices, id: \.self) { seconds in
                            Text("\(seconds) seconds").tag(seconds)
                        }
                    }
                }
            }

            InterfaceSection(nil) {
                InterfaceToggleRow("Close after dragging", detail: "Hold Option while dragging to keep the card.", isOn: $closeAfterDragging)
                InterfaceToggleRow("Close after uploading", isOn: $closeAfterUploading)
                InterfacePickerRow("Save button", selection: saveButtonUsesFolderBinding) {
                    Text("Save to Export Folder").tag(true)
                    Text("Ask Where to Save").tag(false)
                }
                if !accessibilityGranted {
                    InterfaceRow("Card shortcuts in other apps") {
                        Button("Enable…") {
                            CaptureShelfKeyboardShortcuts.requestAccessibility()
                            accessibilityGranted = CaptureShelfKeyboardShortcuts.accessibilityGranted
                        }
                    }
                }
            }

            InterfaceSection("Swipe Actions") {
                swipePicker("Toward screen edge", selection: $swipeTowardEdgeAction)
                swipePicker("Away from screen edge", selection: $swipeAwayFromEdgeAction)
            }

            InterfaceSection("Card Actions", footer: "Drag actions between the corners, the center, and Hidden.") {
                OverlayCardEditor()
                    .padding(.vertical, Space.m)
            }

            InterfaceSection("Pinned Screenshots") {
                InterfaceToggleRow("Rounded corners", isOn: $pinnedRoundedCorners)
                InterfaceToggleRow("Shadow", isOn: $pinnedShadow)
                InterfaceToggleRow("Border", isOn: $pinnedBorder)
            }
        }
        .motion(.fold, value: autoCloseSeconds > 0)
        .onAppear {
            if autoCloseSeconds > 0 { lastAutoCloseInterval = autoCloseSeconds }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            accessibilityGranted = CaptureShelfKeyboardShortcuts.accessibilityGranted
        }
    }

    private func swipePicker(_ title: String, selection: Binding<QuickAccessSwipeAction>) -> some View {
        InterfacePickerRow(title, selection: selection) {
            ForEach(QuickAccessSwipeAction.allCases) { action in
                Text(action.title).tag(action)
            }
        }
    }

    private var positionBinding: Binding<PreviewOverlayPosition> {
        Binding(
            get: { PreviewOverlayPosition(rawValue: positionRaw) ?? .right },
            set: { positionRaw = $0.rawValue }
        )
    }

    private var autoCloseEnabledBinding: Binding<Bool> {
        Binding(
            get: { autoCloseSeconds > 0 },
            set: { isEnabled in
                if isEnabled {
                    autoCloseSeconds = lastAutoCloseInterval
                } else {
                    if autoCloseSeconds > 0 { lastAutoCloseInterval = autoCloseSeconds }
                    autoCloseSeconds = 0
                }
            }
        )
    }

    private var autoCloseIntervalChoices: [Int] {
        Set(Self.autoCloseIntervals + [autoCloseSeconds].filter { $0 > 0 }).sorted()
    }

    private var saveButtonUsesFolderBinding: Binding<Bool> {
        Binding(
            get: { _ = saveButtonUsesFolder; return UpshotPreferences.saveButtonUsesConfiguredFolder },
            set: { saveButtonUsesFolder = $0 }
        )
    }
}
