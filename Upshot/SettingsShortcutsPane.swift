import SwiftUI

enum SettingsShortcutsGroup: String, CaseIterable, Identifiable {
    case general
    case screenshots
    case recording
    case screenshotEditor
    case recordingEditor
    case library
    case settings
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .screenshots: "Screenshots"
        case .recording: "Screen Recording"
        case .screenshotEditor: "Screenshot Editor"
        case .recordingEditor: "Recording Editor"
        case .library: "Library"
        case .settings: "Settings"
        case .other: "Other"
        }
    }

    var subgroups: [[CaptureHotkeyAction]] {
        switch self {
        case .general:
            [[.allInOne, .toggleDesktopIcons, .captureHistory, .restoreLastCapture]]
        case .screenshots:
            [
                [.area, .previousArea, .fullscreen, .window, .smartElement, .scrollingCapture, .selfTimer, .textCapture],
                [.areaCopy, .areaSave, .areaUpload],
                [.toggleCrosshair, .toggleMagnifier]
            ]
        case .recording:
            [
                [.screenRecording, .recordingToggle, .recordingStart, .recordingStop, .recordingPause, .recordingResume, .recordingRestart, .recordingDiscard],
                [.recordingTogglePen, .recordingClearPen]
            ]
        case .screenshotEditor:
            [
                [.editorOpen, .editorSave, .editorSaveCopy, .editorDone, .editorShare, .editorUndo, .editorRedo, .editorAlwaysOnTop],
                [.editorHighlighter, .editorMeasure, .editorTextPlain, .editorTextLabel, .editorTextCallout, .editorRedactionStyle, .editorDrawingSmoothing, .editorObjectShadows],
                [.editorWatermark, .editorColorAdjustments, .editorRotateClockwise, .editorRotateCounterclockwise, .editorFlipHorizontal, .editorFlipVertical, .editorCombineSideBySide, .editorCombineStacked, .editorExpandCanvas]
            ]
        case .recordingEditor:
            [
                [.recordingEditorOpen, .recordingEditorSave, .recordingEditorUndo, .recordingEditorRedo, .recordingEditorPlay, .recordingEditorPause],
                [.recordingEditorExport, .recordingEditorExportGIF, .recordingEditorExportAudio, .recordingEditorCancelExport]
            ]
        case .library:
            [
                [.library, .libraryScreenshots, .libraryRecordings, .screenshotsFolder, .libraryRefresh],
                [.libraryPreview, .libraryEdit, .libraryRename, .libraryCopy, .libraryCopyText, .libraryDetectCodes, .libraryExport, .libraryReveal, .libraryTrash]
            ]
        case .settings:
            [[.settings, .settingsScreenshots, .settingsVideo, .settingsOverlay, .settingsMCP, .settingsCloud, .settingsAbout]]
        case .other:
            [Self.ungroupedActions]
        }
    }

    private static let ungroupedActions: [CaptureHotkeyAction] = {
        let grouped = Set(allCases.filter { $0 != .other }.flatMap { $0.subgroups.joined() })
        return CaptureHotkeyAction.allCases.filter { !grouped.contains($0) }
    }()
}

private struct SettingsShortcutsSubgroup: Identifiable {
    let id: String
    let title: String?
    let actions: [CaptureHotkeyAction]
}

struct SettingsShortcutsPane: View {
    @State private var model: CaptureHotkeySettingsModel
    @State private var searchText: String

    init(model: CaptureHotkeySettingsModel? = nil, searchText: String = "") {
        _model = State(initialValue: model ?? CaptureHotkeySettingsModel())
        _searchText = State(initialValue: searchText)
    }

    var body: some View {
        let subgroups = visibleSubgroups
        Group {
            if subgroups.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                InterfaceFormPage {
                    ForEach(subgroups) { subgroup in
                        InterfaceSection(subgroup.title) {
                            ForEach(subgroup.actions) { action in
                                CaptureHotkeyShortcutRow(action: action, model: model)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search shortcuts")
        .modifier(CaptureHotkeySettingsLifecycle(model: model))
    }

    private var visibleSubgroups: [SettingsShortcutsSubgroup] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsShortcutsGroup.allCases.flatMap { group in
            let matches = group.subgroups
                .map { actions in actions.filter { query.isEmpty || matchesSearch($0, group: group, query: query) } }
                .filter { !$0.isEmpty }
            return matches.enumerated().map { index, actions in
                SettingsShortcutsSubgroup(id: "\(group.rawValue)-\(index)", title: index == 0 ? group.title : nil, actions: actions)
            }
        }
    }

    private func matchesSearch(_ action: CaptureHotkeyAction, group: SettingsShortcutsGroup, query: String) -> Bool {
        let shortcutText = model.shortcut(for: action)?.displayTokens.joined() ?? ""
        return [action.title, action.route, group.title, shortcutText].contains { $0.localizedStandardContains(query) }
    }
}
