import AppKit
import Carbon.HIToolbox
import Foundation

struct HotkeyShortcut: Codable, Equatable, Hashable {
    struct Modifiers: OptionSet, Codable, Equatable, Hashable {
        let rawValue: Int

        static let command = Modifiers(rawValue: 1 << 0)
        static let option = Modifiers(rawValue: 1 << 1)
        static let control = Modifiers(rawValue: 1 << 2)
        static let shift = Modifiers(rawValue: 1 << 3)

        init(rawValue: Int) {
            self.rawValue = rawValue
        }

        init(from eventFlags: NSEvent.ModifierFlags) {
            var modifiers: Modifiers = []
            if eventFlags.contains(.command) { modifiers.insert(.command) }
            if eventFlags.contains(.option) { modifiers.insert(.option) }
            if eventFlags.contains(.control) { modifiers.insert(.control) }
            if eventFlags.contains(.shift) { modifiers.insert(.shift) }
            self = modifiers
        }

        var carbonEventModifiers: UInt32 {
            var flags: UInt32 = 0
            if contains(.command) { flags |= UInt32(cmdKey) }
            if contains(.option) { flags |= UInt32(optionKey) }
            if contains(.control) { flags |= UInt32(controlKey) }
            if contains(.shift) { flags |= UInt32(shiftKey) }
            return flags
        }

        var symbols: [String] {
            var result: [String] = []
            if contains(.control) { result.append("⌃") }
            if contains(.option) { result.append("⌥") }
            if contains(.shift) { result.append("⇧") }
            if contains(.command) { result.append("⌘") }
            return result
        }
    }

    let modifiers: Modifiers
    let keyCode: Int

    var displayTokens: [String] {
        modifiers.symbols + [Self.keyLabel(for: keyCode)]
    }

    var displayString: String {
        displayTokens.joined(separator: " ")
    }

    var isValid: Bool {
        !modifiers.isEmpty && (0...127).contains(keyCode) && modifiers.rawValue & ~15 == 0
    }

    private static func keyLabel(for keyCode: Int) -> String {
        switch keyCode {
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Space: return "Space"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_Escape: return "⎋"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return ansiKeyLabel(for: keyCode) ?? "Key \(keyCode)"
        }
    }

    private static func ansiKeyLabel(for keyCode: Int) -> String? {
        switch keyCode {
        case kVK_ANSI_A: return "A"
        case kVK_ANSI_B: return "B"
        case kVK_ANSI_C: return "C"
        case kVK_ANSI_D: return "D"
        case kVK_ANSI_E: return "E"
        case kVK_ANSI_F: return "F"
        case kVK_ANSI_G: return "G"
        case kVK_ANSI_H: return "H"
        case kVK_ANSI_I: return "I"
        case kVK_ANSI_J: return "J"
        case kVK_ANSI_K: return "K"
        case kVK_ANSI_L: return "L"
        case kVK_ANSI_M: return "M"
        case kVK_ANSI_N: return "N"
        case kVK_ANSI_O: return "O"
        case kVK_ANSI_P: return "P"
        case kVK_ANSI_Q: return "Q"
        case kVK_ANSI_R: return "R"
        case kVK_ANSI_S: return "S"
        case kVK_ANSI_T: return "T"
        case kVK_ANSI_U: return "U"
        case kVK_ANSI_V: return "V"
        case kVK_ANSI_W: return "W"
        case kVK_ANSI_X: return "X"
        case kVK_ANSI_Y: return "Y"
        case kVK_ANSI_Z: return "Z"
        case kVK_ANSI_0: return "0"
        case kVK_ANSI_1: return "1"
        case kVK_ANSI_2: return "2"
        case kVK_ANSI_3: return "3"
        case kVK_ANSI_4: return "4"
        case kVK_ANSI_5: return "5"
        case kVK_ANSI_6: return "6"
        case kVK_ANSI_7: return "7"
        case kVK_ANSI_8: return "8"
        case kVK_ANSI_9: return "9"
        case kVK_ANSI_Minus: return "-"
        case kVK_ANSI_Equal: return "="
        case kVK_ANSI_LeftBracket: return "["
        case kVK_ANSI_RightBracket: return "]"
        case kVK_ANSI_Backslash: return "\\"
        case kVK_ANSI_Semicolon: return ";"
        case kVK_ANSI_Quote: return "'"
        case kVK_ANSI_Comma: return ","
        case kVK_ANSI_Period: return "."
        case kVK_ANSI_Slash: return "/"
        case kVK_ANSI_Grave: return "`"
        default: return nil
        }
    }
}

enum CaptureHotkeyAction: String, CaseIterable, Identifiable {
    case fullscreen, window, area, screenRecording, textCapture
    case areaCopy, areaSave, areaUpload, selfTimer, previousArea
    case recordingStart, recordingStop, recordingToggle, recordingPause, recordingResume
    case recordingRestart, recordingDiscard
    case editorOpen, recordingEditorOpen
    case library, libraryScreenshots, libraryRecordings, restoreLastCapture
    case settings, settingsScreenshots, settingsVideo, settingsOverlay, settingsMCP, settingsCloud, settingsAbout
    case screenshotsFolder
    case libraryPreview, libraryEdit, libraryRename, libraryCopy, libraryExport, libraryReveal, libraryTrash, libraryRefresh
    case editorSave, editorSaveCopy, editorDone, editorShare, editorUndo, editorRedo
    case recordingEditorSave, recordingEditorUndo, recordingEditorRedo, recordingEditorPlay, recordingEditorPause
    case recordingEditorExport, recordingEditorExportAudio, recordingEditorCancelExport

    case allInOne
    case smartElement
    case scrollingCapture
    case toggleCrosshair
    case toggleMagnifier
    case toggleDesktopIcons
    case captureHistory
    case recordingTogglePen
    case recordingClearPen
    case editorHighlighter
    case editorMeasure
    case editorTextPlain
    case editorTextLabel
    case editorTextCallout
    case editorRedactionStyle
    case editorWatermark
    case editorColorAdjustments
    case editorRotateClockwise
    case editorRotateCounterclockwise
    case editorFlipHorizontal
    case editorFlipVertical
    case editorCombineSideBySide
    case editorCombineStacked
    case editorDrawingSmoothing
    case editorObjectShadows
    case editorExpandCanvas
    case editorAlwaysOnTop
    case recordingEditorExportGIF
    case libraryCopyText
    case libraryDetectCodes

    var id: Self { self }

    var hotKeyID: UInt32 {
        UInt32(Self.allCases.firstIndex(of: self)! + 1)
    }

    var route: String {
        switch self {
        case .allInOne: "capture/all-in-one"
        case .smartElement: "capture/smart-element"
        case .scrollingCapture: "capture/scrolling"
        case .toggleCrosshair: "selection/toggle-crosshair"
        case .toggleMagnifier: "selection/toggle-magnifier"
        case .toggleDesktopIcons: "desktop/toggle-icons"
        case .captureHistory: "library/history"
        case .recordingTogglePen: "recording/toggle-pen"
        case .recordingClearPen: "recording/clear-pen"
        case .editorHighlighter: "editor/highlighter"
        case .editorMeasure: "editor/measure"
        case .editorTextPlain: "editor/text-plain"
        case .editorTextLabel: "editor/text-label"
        case .editorTextCallout: "editor/text-callout"
        case .editorRedactionStyle: "editor/redaction-style"
        case .editorWatermark: "editor/watermark"
        case .editorColorAdjustments: "editor/color-adjustments"
        case .editorRotateClockwise: "editor/rotate-clockwise"
        case .editorRotateCounterclockwise: "editor/rotate-counterclockwise"
        case .editorFlipHorizontal: "editor/flip-horizontal"
        case .editorFlipVertical: "editor/flip-vertical"
        case .editorCombineSideBySide: "editor/combine-side-by-side"
        case .editorCombineStacked: "editor/combine-stacked"
        case .editorDrawingSmoothing: "editor/drawing-smoothing"
        case .editorObjectShadows: "editor/object-shadows"
        case .editorExpandCanvas: "editor/expand-canvas"
        case .editorAlwaysOnTop: "editor/always-on-top"
        case .recordingEditorExportGIF: "editor/recording-export-gif"
        case .libraryCopyText: "library/copy-text"
        case .libraryDetectCodes: "library/detect-codes"
        case .fullscreen: "capture/fullscreen"
        case .window: "capture/window"
        case .area: "capture/area"
        case .textCapture: "capture/text"
        case .areaCopy: "capture/area-copy"
        case .areaSave: "capture/area-save"
        case .areaUpload: "capture/area-upload"
        case .selfTimer: "capture/self-timer"
        case .previousArea: "capture/previous-area"
        case .screenRecording: "recording/picker"
        case .recordingStart: "recording/start"
        case .recordingStop: "recording/stop"
        case .recordingToggle: "recording/toggle"
        case .recordingPause: "recording/pause"
        case .recordingResume: "recording/resume"
        case .recordingRestart: "recording/restart"
        case .recordingDiscard: "recording/discard"
        case .editorOpen: "editor/open"
        case .recordingEditorOpen: "editor/recording"
        case .library: "library/open"
        case .libraryScreenshots: "library/screenshots"
        case .libraryRecordings: "library/recordings"
        case .restoreLastCapture: "library/restore-last"
        case .settings: "settings/general"
        case .settingsScreenshots: "settings/screenshots"
        case .settingsVideo: "settings/video"
        case .settingsOverlay: "settings/overlay"
        case .settingsMCP: "settings/mcp"
        case .settingsCloud: "settings/cloud"
        case .settingsAbout: "settings/about"
        case .screenshotsFolder: "library/folder"
        case .libraryPreview: "library/preview"
        case .libraryEdit: "library/edit"
        case .libraryRename: "library/rename"
        case .libraryCopy: "library/copy"
        case .libraryExport: "library/export"
        case .libraryReveal: "library/reveal"
        case .libraryTrash: "library/trash"
        case .libraryRefresh: "library/refresh"
        case .editorSave: "editor/save"
        case .editorSaveCopy: "editor/save-copy"
        case .editorDone: "editor/done"
        case .editorShare: "editor/share"
        case .editorUndo: "editor/undo"
        case .editorRedo: "editor/redo"
        case .recordingEditorSave: "editor/recording-save"
        case .recordingEditorUndo: "editor/recording-undo"
        case .recordingEditorRedo: "editor/recording-redo"
        case .recordingEditorPlay: "editor/recording-play"
        case .recordingEditorPause: "editor/recording-pause"
        case .recordingEditorExport: "editor/recording-export"
        case .recordingEditorExportAudio: "editor/recording-export-audio"
        case .recordingEditorCancelExport: "editor/recording-cancel-export"
        }
    }

    var title: String {
        switch self {
        case .allInOne: "Capture All-In-One"
        case .smartElement: "Capture Smart Element"
        case .scrollingCapture: "Capture Scrolling"
        case .toggleCrosshair: "Toggle Selection Crosshair"
        case .toggleMagnifier: "Toggle Selection Magnifier"
        case .toggleDesktopIcons: "Toggle Desktop Icons"
        case .captureHistory: "Open Capture History"
        case .recordingTogglePen: "Toggle Recording Live Pen"
        case .recordingClearPen: "Clear Recording Live Pen"
        case .editorHighlighter: "Select Text Highlighter"
        case .editorMeasure: "Select Measure Tool"
        case .editorTextPlain: "Select Plain Text"
        case .editorTextLabel: "Select Label Text"
        case .editorTextCallout: "Select Callout Text"
        case .editorRedactionStyle: "Change Redaction Style"
        case .editorWatermark: "Set Screenshot Watermark"
        case .editorColorAdjustments: "Set Screenshot Color Adjustments"
        case .editorRotateClockwise: "Rotate Screenshot Clockwise"
        case .editorRotateCounterclockwise: "Rotate Screenshot Counterclockwise"
        case .editorFlipHorizontal: "Flip Screenshot Horizontally"
        case .editorFlipVertical: "Flip Screenshot Vertically"
        case .editorCombineSideBySide: "Combine Images Side by Side"
        case .editorCombineStacked: "Combine Images Stacked"
        case .editorDrawingSmoothing: "Set Freehand Smoothing"
        case .editorObjectShadows: "Toggle Annotation Shadows"
        case .editorExpandCanvas: "Toggle Automatic Canvas Expansion"
        case .editorAlwaysOnTop: "Toggle Editor Always on Top"
        case .recordingEditorExportGIF: "Export Recording as GIF"
        case .libraryCopyText: "Copy Text from Selected Capture"
        case .libraryDetectCodes: "Detect Codes in Selected Capture"
        case .fullscreen: "Capture Fullscreen"
        case .window: "Capture Window"
        case .area: "Capture Area"
        case .textCapture: "Capture Text"
        case .areaCopy: "Capture Area and Copy"
        case .areaSave: "Capture Area and Save"
        case .areaUpload: "Capture Area and Upload"
        case .selfTimer: "Capture with Self-timer"
        case .previousArea: "Capture Previous Area"
        case .screenRecording: "Screen Recording"
        case .recordingStart: "Start Screen Recording"
        case .recordingStop: "Stop Screen Recording"
        case .recordingToggle: "Toggle Screen Recording"
        case .recordingPause: "Pause Screen Recording"
        case .recordingResume: "Resume Screen Recording"
        case .recordingRestart: "Restart Screen Recording"
        case .recordingDiscard: "Discard Screen Recording"
        case .editorOpen: "Open Screenshot Editor"
        case .recordingEditorOpen: "Open Recording Editor"
        case .library: "Open Library"
        case .libraryScreenshots: "Open Screenshot Library"
        case .libraryRecordings: "Open Recording Library"
        case .restoreLastCapture: "Restore Last Capture"
        case .settings: "Open General Settings"
        case .settingsScreenshots: "Open Screenshot Settings"
        case .settingsVideo: "Open Recording Settings"
        case .settingsOverlay: "Open Overlay Settings"
        case .settingsMCP: "Open MCP Settings"
        case .settingsCloud: "Open Cloud Settings"
        case .settingsAbout: "Open About"
        case .screenshotsFolder: "Open Screenshots Folder"
        case .libraryPreview: "Preview Selected Capture"
        case .libraryEdit: "Edit Selected Capture"
        case .libraryRename: "Rename Selected Capture"
        case .libraryCopy: "Copy Selected Captures"
        case .libraryExport: "Export Selected Captures"
        case .libraryReveal: "Reveal Selected Captures"
        case .libraryTrash: "Trash Selected Captures"
        case .libraryRefresh: "Refresh Library"
        case .editorSave: "Save Screenshot Edits"
        case .editorSaveCopy: "Save Screenshot Copy"
        case .editorDone: "Save and Close Screenshot"
        case .editorShare: "Share Edited Screenshot"
        case .editorUndo: "Undo Screenshot Edit"
        case .editorRedo: "Redo Screenshot Edit"
        case .recordingEditorSave: "Save Recording Edits"
        case .recordingEditorUndo: "Undo Recording Edit"
        case .recordingEditorRedo: "Redo Recording Edit"
        case .recordingEditorPlay: "Play Recording Preview"
        case .recordingEditorPause: "Pause Recording Preview"
        case .recordingEditorExport: "Export Edited Recording"
        case .recordingEditorExportAudio: "Export Recording Audio"
        case .recordingEditorCancelExport: "Cancel Recording Export"
        }
    }

    var defaultShortcut: HotkeyShortcut? {
        switch self {
        case .allInOne: HotkeyShortcut(modifiers: [.command, .shift], keyCode: Int(kVK_ANSI_5))
        default: nil
        }
    }

    var preferencesKey: String { "captureHotkey.\(rawValue)" }

    init?(hotKeyID: UInt32) {
        guard let action = Self.allCases.first(where: { $0.hotKeyID == hotKeyID }) else { return nil }
        self = action
    }

    func perform() {
        Task { @MainActor in
            do {
                _ = try await AutomationActions.perform(self)
            } catch AutomationError.cancelled {
                AppLog.event("settings", "automation_action_cancelled", fields: ["action": String(describing: route)])
            } catch {
                AppLog.event("settings", "automation_action_failed", fields: ["action": String(describing: route), "error": AppLog.error(error)])
                AppAlerts.shortcutActionFailed(actionTitle: title, error: error).runModal()
            }
        }
    }
}

enum CaptureHotkeyPreferences {
    static func shortcut(for action: CaptureHotkeyAction, defaults: UserDefaults = UpshotStorage.defaults) -> HotkeyShortcut? {
        if defaults.string(forKey: action.preferencesKey) == "disabled" { return nil }
        guard let data = defaults.data(forKey: action.preferencesKey),
              let shortcut = try? JSONDecoder().decode(HotkeyShortcut.self, from: data),
              shortcut.isValid else { return action.defaultShortcut }
        return shortcut
    }

    static func saveShortcut(_ shortcut: HotkeyShortcut?, for action: CaptureHotkeyAction, defaults: UserDefaults = UpshotStorage.defaults) {
        if shortcut == action.defaultShortcut {
            defaults.removeObject(forKey: action.preferencesKey)
        } else if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: action.preferencesKey)
        } else {
            defaults.set("disabled", forKey: action.preferencesKey)
        }
    }

    static func shortcuts(for actions: [CaptureHotkeyAction] = CaptureHotkeyAction.allCases, defaults: UserDefaults = UpshotStorage.defaults) -> [CaptureHotkeyAction: HotkeyShortcut] {
        Dictionary(uniqueKeysWithValues: actions.compactMap { action in
            shortcut(for: action, defaults: defaults).map { (action, $0) }
        })
    }

    static func conflictingAction(for shortcut: HotkeyShortcut, excluding action: CaptureHotkeyAction, defaults: UserDefaults = UpshotStorage.defaults) -> CaptureHotkeyAction? {
        CaptureHotkeyAction.allCases.first { $0 != action && self.shortcut(for: $0, defaults: defaults) == shortcut }
    }
}
