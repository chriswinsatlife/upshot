import AppKit
import SwiftUI

enum MenuBarMenuRenderState: String, CaseIterable {
    case menuBar = "menu-bar"
    case captureActions = "menu-capture-actions"
    case recordingControls = "menu-recording-controls"
    case history = "menu-history"
    case projects = "menu-projects"
    case libraryActions = "menu-library-actions"
    case screenshotEditorActions = "menu-screenshot-editor-actions"
    case recordingEditorActions = "menu-recording-editor-actions"
    case settingsPanes = "menu-settings-panes"

    var openSubmenuTitle: String? {
        switch self {
        case .menuBar: nil
        case .captureActions: MenuBarView.captureActionsTitle
        case .recordingControls: MenuBarView.recordingControlsTitle
        case .history: MenuBarView.recentCapturesTitle
        case .projects: MenuBarView.recordingsTitle
        case .libraryActions: MenuBarView.libraryActionsTitle
        case .screenshotEditorActions: MenuBarView.screenshotEditorActionsTitle
        case .recordingEditorActions: MenuBarView.recordingEditorActionsTitle
        case .settingsPanes: MenuBarView.settingsPanesTitle
        }
    }

    var size: CGSize {
        CGSize(width: openSubmenuTitle == nil ? 420 : 760, height: self == .screenshotEditorActions ? 1180 : 860)
    }
}

struct MenuBarMenuSnapshotItem: Identifiable {
    let id: Int
    let title: String
    let image: NSImage?
    let keyEquivalentText: String
    let isSeparator: Bool
    let isSectionHeader: Bool
    let isEnabled: Bool
    let submenu: [MenuBarMenuSnapshotItem]?

    init(item: NSMenuItem, index: Int) {
        id = index
        title = item.title
        image = item.image
        keyEquivalentText = Self.keyEquivalentText(for: item)
        isSeparator = item.isSeparatorItem
        isSectionHeader = item.isSectionHeader
        isEnabled = item.isEnabled
        submenu = item.submenu.map(MenuBarMenuSnapshotItem.items(in:))
    }

    static func items(in menu: NSMenu) -> [MenuBarMenuSnapshotItem] {
        menu.update()
        return menu.items.enumerated().map { MenuBarMenuSnapshotItem(item: $1, index: $0) }
    }

    var allTitles: [String] {
        [title] + (submenu ?? []).flatMap(\.allTitles)
    }

    private static func keyEquivalentText(for item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return "" }
        var modifiers = item.keyEquivalentModifierMask
        if key.count == 1, let character = key.first, character.isUppercase { modifiers.insert(.shift) }
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + keyLabel(for: key)
    }

    private static func keyLabel(for key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return key }
        switch Int(scalar.value) {
        case 0x0D, 0x03: return "↩"
        case 0x09: return "⇥"
        case 0x20: return "Space"
        case 0x08, 0x7F: return "⌫"
        case NSDeleteFunctionKey: return "⌦"
        case 0x1B: return "⎋"
        case NSLeftArrowFunctionKey: return "←"
        case NSRightArrowFunctionKey: return "→"
        case NSUpArrowFunctionKey: return "↑"
        case NSDownArrowFunctionKey: return "↓"
        case NSF1FunctionKey...NSF12FunctionKey: return "F\(Int(scalar.value) - NSF1FunctionKey + 1)"
        default: return key.uppercased()
        }
    }
}

enum MenuBarMenuRendering {
    static func makeView(for state: MenuBarMenuRenderState) async -> AnyView {
        precondition(UpshotStorage.isRenderingStates)
        let recordingManager = ScreenRecordingManager.shared
        recordingManager.state = state == .recordingControls ? .recording : .idle
        recordingManager.elapsedTime = state == .recordingControls ? 84 : 0
        assignFixtureShortcuts()
        ScreenshotHistoryStore.shared.reload()
        RecordingProjectStore.shared.reload()
        await waitUntil { !RecordingProjectStore.shared.projects.isEmpty }
        let menu = NSHostingMenu(rootView: MenuBarView().defaultAppStorage(UpshotStorage.defaults))
        await waitUntil {
            menu.update()
            return menu.items.contains { $0.title == MenuBarView.quitTitle }
        }
        try? await Task.sleep(for: .milliseconds(200))
        let items = MenuBarMenuSnapshotItem.items(in: menu)
        logCoverage(items: items, state: state)
        logMetrics()
        return AnyView(MenuBarMenuRenderView(items: items, openSubmenuTitle: state.openSubmenuTitle))
    }

    private static func assignFixtureShortcuts() {
        let fixtureShortcuts: [(CaptureHotkeyAction, HotkeyShortcut)] = [
            (.fullscreen, HotkeyShortcut(modifiers: [.option], keyCode: 18)),
            (.window, HotkeyShortcut(modifiers: [.option], keyCode: 19)),
            (.area, HotkeyShortcut(modifiers: [.option], keyCode: 20)),
            (.screenRecording, HotkeyShortcut(modifiers: [.option], keyCode: 21)),
            (.textCapture, HotkeyShortcut(modifiers: [.option], keyCode: 23)),
            (.previousArea, HotkeyShortcut(modifiers: [.option, .shift], keyCode: 20)),
            (.recordingStop, HotkeyShortcut(modifiers: [.command, .shift], keyCode: 53)),
            (.recordingPause, HotkeyShortcut(modifiers: [.option, .shift], keyCode: 35)),
            (.editorUndo, HotkeyShortcut(modifiers: [.control, .option], keyCode: 6)),
            (.recordingEditorPlay, HotkeyShortcut(modifiers: [.control, .option], keyCode: 49)),
            (.captureHistory, HotkeyShortcut(modifiers: [.option], keyCode: 22))
        ]
        for (action, shortcut) in fixtureShortcuts {
            CaptureHotkeyPreferences.saveShortcut(shortcut, for: action)
        }
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<100 {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func logCoverage(items: [MenuBarMenuSnapshotItem], state: MenuBarMenuRenderState) {
        let titles = Set(items.flatMap(\.allTitles))
        let missing = CaptureHotkeyAction.allCases.filter { !titles.contains(MenuBarView.menuTitle(for: $0)) }
        let unlisted = CaptureHotkeyAction.allCases.filter { !MenuBarView.menuActions.contains($0) }
        let duplicated = Dictionary(grouping: MenuBarView.menuActions, by: { $0 }).filter { $0.value.count > 1 }.keys
        let shortcutTitles = items.flatMap(\.flattened).filter { !$0.keyEquivalentText.isEmpty }.map { "\($0.title)=\($0.keyEquivalentText)" }
        let symbolless = items.filter { !$0.isSeparator && $0.image == nil }.map(\.title)
        FileHandle.standardError.write(Data((
            "menu_bar_render state=\(state.rawValue) actions=\(CaptureHotkeyAction.allCases.count) reachable=\(CaptureHotkeyAction.allCases.count - missing.count) "
            + "missing=[\(missing.map(\.rawValue).joined(separator: ","))] unlisted=[\(unlisted.map(\.rawValue).joined(separator: ","))] "
            + "duplicated=[\(duplicated.map(\.rawValue).joined(separator: ","))] top_level_without_symbol=[\(symbolless.joined(separator: ","))] "
            + "shortcuts=[\(shortcutTitles.joined(separator: "; "))]\n"
        ).utf8))
    }

    private static func logMetrics() {
        func measured(_ build: (NSMenu) -> Void) -> CGSize {
            let menu = NSMenu()
            build(menu)
            return menu.size
        }
        let one = measured { $0.addItem(withTitle: "Capture Area", action: nil, keyEquivalent: "") }
        let two = measured { menu in
            menu.addItem(withTitle: "Capture Area", action: nil, keyEquivalent: "")
            menu.addItem(withTitle: "Capture Window", action: nil, keyEquivalent: "")
        }
        let separated = measured { menu in
            menu.addItem(withTitle: "Capture Area", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Capture Window", action: nil, keyEquivalent: "")
        }
        FileHandle.standardError.write(Data(
            "menu_bar_render_metrics one=\(one) two=\(two) separated=\(separated) font=\(NSFont.menuFont(ofSize: 0).pointSize)\n".utf8
        ))
    }
}

private extension MenuBarMenuSnapshotItem {
    var flattened: [MenuBarMenuSnapshotItem] {
        [self] + (submenu ?? []).flatMap(\.flattened)
    }
}

struct MenuBarMenuRenderView: View {
    let items: [MenuBarMenuSnapshotItem]
    let openSubmenuTitle: String?

    private let rowHeight: CGFloat = 24
    private let separatorHeight: CGFloat = 11
    private let menuPadding: CGFloat = 5

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MenuBarStripView()
            HStack(alignment: .top, spacing: -2) {
                menuPanel(items, highlightedTitle: openSubmenuTitle)
                    .padding(.leading, 16)
                if let openSubmenuTitle, let index = items.firstIndex(where: { $0.title == openSubmenuTitle }),
                   let submenu = items[index].submenu {
                    menuPanel(submenu, highlightedTitle: nil)
                        .padding(.top, offset(before: index) - menuPadding)
                }
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func offset(before index: Int) -> CGFloat {
        menuPadding + items.prefix(index).reduce(0) { $0 + ($1.isSeparator ? separatorHeight : rowHeight) }
    }

    private func menuPanel(_ items: [MenuBarMenuSnapshotItem], highlightedTitle: String?) -> some View {
        let reservesSymbolColumn = items.contains { $0.image != nil }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(items) { item in
                if item.isSeparator {
                    Rectangle()
                        .fill(Color(nsColor: .separatorColor))
                        .frame(height: 1)
                        .padding(.horizontal, 10)
                        .frame(height: separatorHeight)
                } else {
                    MenuBarMenuRenderRow(item: item, isHighlighted: item.title == highlightedTitle,
                                         reservesSymbolColumn: reservesSymbolColumn, height: rowHeight)
                }
            }
        }
        .padding(menuPadding)
        .fixedSize()
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 6)
    }
}

private struct MenuBarMenuRenderRow: View {
    let item: MenuBarMenuSnapshotItem
    let isHighlighted: Bool
    let reservesSymbolColumn: Bool
    let height: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            if reservesSymbolColumn {
                Group {
                    if let image = item.image {
                        Image(nsImage: image).renderingMode(.template)
                    }
                }
                .frame(width: 22, alignment: .leading)
            }
            Text(item.title)
                .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
                .fixedSize()
            Spacer(minLength: 28)
            if !item.keyEquivalentText.isEmpty {
                Text(item.keyEquivalentText)
                    .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
                    .foregroundStyle(isHighlighted ? Color.white.opacity(0.85) : Color(nsColor: .tertiaryLabelColor))
                    .fixedSize()
            }
            if item.submenu != nil {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.leading, 6)
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, 9)
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isHighlighted ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var foreground: Color {
        if isHighlighted { return .white }
        if item.isSectionHeader { return Color(nsColor: .secondaryLabelColor) }
        return item.isEnabled ? Color(nsColor: .labelColor) : Color(nsColor: .tertiaryLabelColor)
    }
}

private struct MenuBarStripView: View {
    var body: some View {
        HStack(spacing: 0) {
            RecordingMenuBarLabel()
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Color.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .padding(.leading, 12)
            Spacer(minLength: 0)
        }
        .frame(height: 30)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
        }
    }
}
