import AppKit
import Combine
import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @State private var historyStore = ScreenshotHistoryStore.shared
    @State private var projectStore = RecordingProjectStore.shared
    @State private var recordingManager = ScreenRecordingManager.shared
    @State private var hotkeyManager = HotkeyManager.shared
    @State private var shortcuts = CaptureHotkeyPreferences.shortcuts()

    var body: some View {
        Group {
            actionButton(.area, symbol: "rectangle.dashed") { CaptureCoordinator.shared.captureArea() }
            actionButton(.fullscreen, symbol: "camera") { CaptureCoordinator.shared.captureFullscreen() }
            actionButton(.window, symbol: "macwindow") { CaptureCoordinator.shared.captureWindow() }
            actionButton(.allInOne, symbol: "viewfinder")
            actionButton(.scrollingCapture, symbol: "arrow.down.to.line")
            actionButton(.selfTimer, symbol: "timer")
            actionButton(.textCapture, symbol: "text.viewfinder") { CaptureCoordinator.shared.captureText() }
            actionButton(.screenRecording, symbol: "record.circle") { RecordingPickerPresenter.shared.show() }

            actionMenu(Self.captureActionsTitle, symbol: "ellipsis.circle", groups: Self.captureActionGroups)
            actionMenu(Self.recordingControlsTitle, symbol: "pause.circle", groups: Self.recordingControlGroups)

            Divider()

            actionButton(.toggleDesktopIcons, symbol: "eye")

            Divider()

            actionButton(.library, symbol: "square.grid.2x2", fallbackShortcut: KeyboardShortcut("l", modifiers: [.command, .shift])) {
                CaptureLibraryModel.shared.show()
            }
            actionButton(.captureHistory, symbol: "clock.arrow.circlepath")
            actionButton(.restoreLastCapture, symbol: "arrow.uturn.backward")

            Menu {
                historyMenuContent
            } label: {
                MenuBarItemLabel(Self.recentCapturesTitle, symbol: "photo")
            }

            Menu {
                projectsMenuContent
            } label: {
                MenuBarItemLabel(Self.recordingsTitle, symbol: "film.stack")
            }

            actionButton(.screenshotsFolder, symbol: "folder") { openScreenshotsFolder() }

            Divider()

            actionMenu(Self.libraryActionsTitle, symbol: "rectangle.stack", groups: Self.libraryActionGroups)
            actionMenu(Self.screenshotEditorActionsTitle, symbol: "pencil.tip.crop.circle", groups: Self.screenshotEditorActionGroups)
            actionMenu(Self.recordingEditorActionsTitle, symbol: "film", groups: Self.recordingEditorActionGroups)

            Divider()

            actionButton(.settingsAbout, symbol: "info.circle")

            Divider()

            actionButton(.settings, symbol: "gearshape", fallbackShortcut: KeyboardShortcut(",", modifiers: [.command])) {
                SettingsWindowController.show(tab: .general)
            }
            actionMenu(Self.settingsPanesTitle, symbol: "sidebar.left", groups: Self.settingsPaneGroups)

            Button {
                updaterManager.checkForUpdates()
            } label: {
                MenuBarItemLabel(Self.checkForUpdatesTitle, symbol: "arrow.down.circle")
            }
            .disabled(!updaterManager.canCheckForUpdates)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                MenuBarItemLabel(Self.quitTitle, symbol: "power")
            }
            .keyboardShortcut("q")
        }
        .task {
            historyStore.reload()
            projectStore.reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let latest = CaptureHotkeyPreferences.shortcuts()
            if latest != shortcuts { shortcuts = latest }
        }
    }

    private func actionButton(
        _ action: CaptureHotkeyAction,
        symbol: String? = nil,
        fallbackShortcut: KeyboardShortcut? = nil,
        perform: (() -> Void)? = nil
    ) -> some View {
        Button {
            if let perform { perform() } else { action.perform() }
        } label: {
            if let symbol {
                MenuBarItemLabel(Self.menuTitle(for: action), symbol: symbol)
            } else {
                Text(Self.menuTitle(for: action))
            }
        }
        .keyboardShortcut(menuShortcut(for: action) ?? fallbackShortcut)
        .disabled(!isAvailable(action))
    }

    private func actionMenu(_ title: String, symbol: String, groups: [[CaptureHotkeyAction]]) -> some View {
        Menu {
            ForEach(groups.indices, id: \.self) { index in
                if index > 0 { Divider() }
                ForEach(groups[index]) { action in
                    actionButton(action)
                }
            }
        } label: {
            MenuBarItemLabel(title, symbol: symbol)
        }
    }

    private func menuShortcut(for action: CaptureHotkeyAction) -> KeyboardShortcut? {
        guard hotkeyManager.registrationErrors[action] == nil else { return nil }
        return shortcuts[action]?.menuKeyboardShortcut
    }

    private func isAvailable(_ action: CaptureHotkeyAction) -> Bool {
        let state = recordingManager.state
        switch action {
        case .recordingStart:
            return !recordingManager.isActive
        case .recordingToggle:
            return [.idle, .recording, .paused].contains(state)
        case .recordingStop, .recordingRestart, .recordingDiscard:
            return [.recording, .paused].contains(state)
        case .recordingPause, .recordingTogglePen, .recordingClearPen:
            return state == .recording
        case .recordingResume:
            return state == .paused
        default:
            return true
        }
    }

    @ViewBuilder
    private var projectsMenuContent: some View {
        if projectStore.projects.isEmpty {
            Text("No Recordings")
        } else {
            ForEach(projectStore.recentProjects) { project in
                Button(projectMenuTitle(for: project)) {
                    RecordingProjectOpener.shared.open(project.session)
                }
            }
        }

        Divider()

        Button("Show All Recordings…") {
            CaptureLibraryModel.shared.show(filter: .recordings)
        }
    }

    private func projectMenuTitle(for project: RecordingProjectSummary) -> String {
        let name = truncatedMenuTitle(project.displayName)
        return project.hasUnsavedDraft ? "\(name) - Unsaved" : name
    }

    @ViewBuilder
    private var historyMenuContent: some View {
        if historyStore.recentItems.isEmpty {
            Text("No Captures")
        } else {
            ForEach(historyStore.recentItems) { item in
                Button(historyMenuTitle(for: item)) {
                    showHistoryPreview(item)
                }
            }
        }

        Divider()

        Button("Show All Captures…") {
            CaptureLibraryModel.shared.show(filter: .all)
        }
    }

    private func showHistoryPreview(_ item: ScreenshotHistoryItem) {
        if item.isVideo {
            CaptureShelf.shared.show(existing: item.url, kind: .video)
        } else {
            CaptureShelf.shared.show(existing: item.url, kind: .image)
        }
        CaptureShelfPresenter.shared.show(displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: false))
    }

    private func openScreenshotsFolder() {
        let directory = UpshotPreferences.exportDirectory

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            showOpenScreenshotsFolderError(directory: directory, errorDescription: error.localizedDescription)
            return
        }

        if !NSWorkspace.shared.open(directory) {
            showOpenScreenshotsFolderError(directory: directory, errorDescription: nil)
        }
    }

    private func showOpenScreenshotsFolderError(directory: URL, errorDescription: String?) {
        AppAlerts.screenshotsFolderFailed(directory: directory, errorDescription: errorDescription).runModal()
    }

    private func historyMenuTitle(for item: ScreenshotHistoryItem) -> String {
        let name = item.displayName ?? item.fileName
        let limit = 30

        guard name.count > limit else {
            return name
        }

        let url = URL(fileURLWithPath: name)
        let pathExtension = url.pathExtension
        let suffix = pathExtension.isEmpty ? "" : ".\(pathExtension)"
        let baseName = url.deletingPathExtension().lastPathComponent
        let allowedBaseLength = max(8, limit - suffix.count - 3)

        return "\(baseName.prefix(allowedBaseLength))…\(suffix)"
    }

    private func truncatedMenuTitle(_ name: String) -> String {
        let limit = 34
        guard name.count > limit else { return name }
        return "\(name.prefix(limit - 1))…"
    }
}

extension MenuBarView {
    static let captureActionsTitle = "Capture Actions"
    static let recordingControlsTitle = "Recording Controls"
    static let recentCapturesTitle = "Recent Captures"
    static let recordingsTitle = "Recordings"
    static let libraryActionsTitle = "Library Actions"
    static let screenshotEditorActionsTitle = "Screenshot Editor Actions"
    static let recordingEditorActionsTitle = "Recording Editor Actions"
    static let settingsPanesTitle = "Settings Panes"
    static let checkForUpdatesTitle = "Check for Updates…"
    static let quitTitle = "Quit Upshot"

    static let topLevelActions: [CaptureHotkeyAction] = [
        .area, .fullscreen, .window, .allInOne, .scrollingCapture, .selfTimer, .textCapture, .screenRecording,
        .toggleDesktopIcons,
        .library, .captureHistory, .restoreLastCapture, .screenshotsFolder,
        .settingsAbout, .settings
    ]

    static let captureActionGroups: [[CaptureHotkeyAction]] = [
        [.smartElement, .previousArea],
        [.areaCopy, .areaSave, .areaUpload],
        [.toggleCrosshair, .toggleMagnifier]
    ]

    static let recordingControlGroups: [[CaptureHotkeyAction]] = [
        [.recordingStart, .recordingStop, .recordingToggle],
        [.recordingPause, .recordingResume, .recordingRestart, .recordingDiscard],
        [.recordingTogglePen, .recordingClearPen]
    ]

    static let libraryActionGroups: [[CaptureHotkeyAction]] = [
        [.libraryScreenshots, .libraryRecordings, .libraryRefresh],
        [.libraryPreview, .libraryEdit, .libraryRename, .libraryCopy, .libraryExport, .libraryReveal, .libraryTrash],
        [.libraryCopyText, .libraryDetectCodes]
    ]

    static let screenshotEditorActionGroups: [[CaptureHotkeyAction]] = [
        [.editorOpen],
        [.editorSave, .editorSaveCopy, .editorDone, .editorShare],
        [.editorUndo, .editorRedo],
        [.editorHighlighter, .editorMeasure, .editorTextPlain, .editorTextLabel, .editorTextCallout, .editorRedactionStyle],
        [.editorRotateClockwise, .editorRotateCounterclockwise, .editorFlipHorizontal, .editorFlipVertical,
         .editorCombineSideBySide, .editorCombineStacked],
        [.editorWatermark, .editorColorAdjustments, .editorDrawingSmoothing, .editorObjectShadows,
         .editorExpandCanvas, .editorAlwaysOnTop]
    ]

    static let recordingEditorActionGroups: [[CaptureHotkeyAction]] = [
        [.recordingEditorOpen],
        [.recordingEditorPlay, .recordingEditorPause],
        [.recordingEditorUndo, .recordingEditorRedo, .recordingEditorSave],
        [.recordingEditorExport, .recordingEditorExportGIF, .recordingEditorExportAudio, .recordingEditorCancelExport]
    ]

    static let settingsPaneGroups: [[CaptureHotkeyAction]] = [
        [.settingsScreenshots, .settingsVideo, .settingsOverlay, .settingsMCP, .settingsCloud]
    ]

    static var menuActions: [CaptureHotkeyAction] {
        topLevelActions + [
            captureActionGroups, recordingControlGroups, libraryActionGroups,
            screenshotEditorActionGroups, recordingEditorActionGroups, settingsPaneGroups
        ].flatMap { $0.flatMap { $0 } }
    }

    static func menuTitle(for action: CaptureHotkeyAction) -> String {
        switch action {
        case .screenRecording: "Record Screen"
        case .settingsAbout: "About Upshot"
        case .settings: "Settings…"
        case .settingsScreenshots: SettingsTab.screenshots.title
        case .settingsVideo: SettingsTab.screenRecording.title
        case .settingsOverlay: SettingsTab.quickAccess.title
        case .settingsMCP: SettingsTab.mcp.title
        case .settingsCloud: SettingsTab.cloud.title
        default: action.title
        }
    }
}

private extension HotkeyShortcut {
    var menuKeyboardShortcut: KeyboardShortcut? {
        guard isValid, let token = displayTokens.last, let key = Self.menuKeyEquivalent(for: token) else { return nil }
        var eventModifiers: EventModifiers = []
        if modifiers.contains(.command) { eventModifiers.insert(.command) }
        if modifiers.contains(.option) { eventModifiers.insert(.option) }
        if modifiers.contains(.control) { eventModifiers.insert(.control) }
        if modifiers.contains(.shift) { eventModifiers.insert(.shift) }
        return KeyboardShortcut(key, modifiers: eventModifiers)
    }

    static func menuKeyEquivalent(for token: String) -> KeyEquivalent? {
        switch token {
        case "↩": return .return
        case "⇥": return .tab
        case "Space": return .space
        case "⌫": return .delete
        case "⌦": return .deleteForward
        case "⎋": return .escape
        case "←": return .leftArrow
        case "→": return .rightArrow
        case "↑": return .upArrow
        case "↓": return .downArrow
        default:
            if token.count > 1, token.first == "F", let number = Int(token.dropFirst()), (1...12).contains(number),
               let scalar = UnicodeScalar(NSF1FunctionKey + number - 1) {
                return KeyEquivalent(Character(scalar))
            }
            guard token.count == 1, let character = token.lowercased().first else { return nil }
            return KeyEquivalent(character)
        }
    }
}
