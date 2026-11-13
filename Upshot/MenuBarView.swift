import AppKit
import Combine
import SwiftUI

struct MenuBarView: View {
    @ObservedObject private var updaterManager = UpdaterManager.shared
    @State private var historyStore = ScreenshotHistoryStore.shared
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

            Divider()

            actionButton(.library, symbol: "square.grid.2x2", fallbackShortcut: KeyboardShortcut("l", modifiers: [.command, .shift])) {
                CaptureLibraryModel.shared.show()
            }

            Menu {
                historyMenuContent
            } label: {
                MenuBarItemLabel(Self.recentCapturesTitle, symbol: "photo")
            }

            actionButton(.screenshotsFolder, symbol: "folder") { openScreenshotsFolder() }

            Divider()

            actionButton(.settings, symbol: "gearshape", fallbackShortcut: KeyboardShortcut(",", modifiers: [.command])) {
                SettingsWindowController.show(tab: .general)
            }

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
    }

    private func menuShortcut(for action: CaptureHotkeyAction) -> KeyboardShortcut? {
        guard hotkeyManager.registrationErrors[action] == nil else { return nil }
        return shortcuts[action]?.menuKeyboardShortcut
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
}

extension MenuBarView {
    static let recentCapturesTitle = "Recent Captures"
    static let checkForUpdatesTitle = "Check for Updates…"
    static let quitTitle = "Quit Upshot"

    static let menuActions: [CaptureHotkeyAction] = [
        .area, .fullscreen, .window, .allInOne, .scrollingCapture, .selfTimer, .textCapture, .screenRecording,
        .library, .screenshotsFolder, .settings
    ]

    static func menuTitle(for action: CaptureHotkeyAction) -> String {
        switch action {
        case .screenRecording: "Record Screen"
        case .settings: "Settings…"
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
