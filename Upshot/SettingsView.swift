import AppKit
import SwiftUI

enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case shortcuts
    case quickAccess = "overlay"
    case screenshots
    case screenRecording = "video"
    case annotate
    case textRecognition = "text-recognition"
    case cloud
    case mcp
    case advanced
    case about

    var id: Self { self }

    static let sidebarGroups: [[SettingsTab]] = [
        [.general, .shortcuts],
        [.quickAccess, .screenshots, .screenRecording, .annotate, .textRecognition],
        [.cloud, .mcp, .advanced]
    ]

    static let sidebarFooterTab: SettingsTab = .about

    static let sidebarOrder: [SettingsTab] = sidebarGroups.flatMap { $0 } + [sidebarFooterTab]

    var title: String {
        switch self {
        case .general: "General"
        case .shortcuts: "Shortcuts"
        case .quickAccess: "Quick Access"
        case .screenshots: "Screenshots"
        case .screenRecording: "Screen Recording"
        case .annotate: "Annotate"
        case .textRecognition: "Text Recognition"
        case .cloud: "Cloud"
        case .mcp: "MCP"
        case .advanced: "Advanced"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .quickAccess: "square.on.square"
        case .screenshots: "camera"
        case .screenRecording: "video"
        case .annotate: "pencil.tip.crop.circle.fill"
        case .textRecognition: "text.viewfinder"
        case .cloud: "icloud"
        case .mcp: "point.3.filled.connected.trianglepath.dotted"
        case .advanced: "wrench.and.screwdriver.fill"
        case .about: "info.circle"
        }
    }

    var tint: Color {
        switch self {
        case .general, .shortcuts, .about: InterfaceSidebarTint.gray
        case .quickAccess: InterfaceSidebarTint.green
        case .screenshots: InterfaceSidebarTint.blue
        case .screenRecording: InterfaceSidebarTint.red
        case .annotate: InterfaceSidebarTint.orange
        case .textRecognition: InterfaceSidebarTint.indigo
        case .cloud: InterfaceSidebarTint.teal
        case .mcp: InterfaceSidebarTint.pink
        case .advanced: InterfaceSidebarTint.purple
        }
    }
}

@MainActor
@Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()

    var selectedTab: SettingsTab = .general
    var searchText = ""
    private(set) var renderDetail: AnyView?

    private init() {}

    func prepareRenderState(selectedTab: SettingsTab, searchText: String = "", detail: AnyView? = nil) {
        assert(UpshotStorage.isRenderingStates)
        self.selectedTab = selectedTab
        self.searchText = searchText
        renderDetail = detail
    }
}

struct SettingsView: View {
    @State private var navigation = SettingsNavigation.shared
    @State private var permissions = SettingsPermissions()
    @State private var navigationHistory: [SettingsTab] = [.general]
    @State private var historyIndex = 0
    @State private var isHistoryNavigation = false

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(navigation: navigation, permissions: permissions)
                .frame(width: InterfaceMetrics.sidebarWidth)
                .navigationSplitViewColumnWidth(
                    min: InterfaceMetrics.sidebarWidth,
                    ideal: InterfaceMetrics.sidebarWidth,
                    max: InterfaceMetrics.sidebarWidth
                )
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailView(tab: navigation.selectedTab, renderDetail: navigation.renderDetail)
                .environment(permissions)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 660, minHeight: 540)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(!canGoBack)
                .help("Go Back")
                .accessibilityLabel("Go Back")

                Button {
                    goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(!canGoForward)
                .help("Go Forward")
                .accessibilityLabel("Go Forward")
            }
        }
        .onAppear {
            navigationHistory = [navigation.selectedTab]
            historyIndex = 0
            permissions.beginWatching()
        }
        .onDisappear { permissions.endWatching() }
        .onChange(of: navigation.selectedTab) { _, _ in
            recordNavigation()
        }
    }

    private var canGoBack: Bool {
        historyIndex > 0
    }

    private var canGoForward: Bool {
        historyIndex < navigationHistory.count - 1
    }

    private func goBack() {
        guard canGoBack else { return }
        isHistoryNavigation = true
        historyIndex -= 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func goForward() {
        guard canGoForward else { return }
        isHistoryNavigation = true
        historyIndex += 1
        navigation.selectedTab = navigationHistory[historyIndex]
        DispatchQueue.main.async { isHistoryNavigation = false }
    }

    private func recordNavigation() {
        guard !isHistoryNavigation else { return }
        let tab = navigation.selectedTab
        if navigationHistory[historyIndex] == tab { return }
        if historyIndex < navigationHistory.count - 1 {
            navigationHistory = Array(navigationHistory.prefix(historyIndex + 1))
        }
        navigationHistory.append(tab)
        historyIndex = navigationHistory.count - 1
    }
}

private struct SettingsSidebar: View {
    @Bindable var navigation: SettingsNavigation
    let permissions: SettingsPermissions

    @FocusState private var isSidebarFocused: Bool

    private static let searchResultsPerTab = 4

    private var searchResults: [SettingsSearchEntry] {
        SettingsSearchEntry.matching(navigation.searchText)
    }

    private var isSearching: Bool {
        !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            InterfaceSidebar(searchPrompt: "Search Settings", searchText: $navigation.searchText) {
                if isSearching {
                    searchResultRows
                } else {
                    tabRows
                }
            }
            .onSubmit {
                if let first = searchResults.first { open(first) }
            }
            footerRows
        }
        .padding(.top, Space.xs)
        .focusable()
        .focusEffectDisabled()
        .focused($isSidebarFocused)
        .onMoveCommand(perform: moveSelection)
    }

    @ViewBuilder
    private var tabRows: some View {
        ForEach(Array(SettingsTab.sidebarGroups.enumerated()), id: \.offset) { index, group in
            if index > 0 {
                Spacer()
                    .frame(height: InterfaceMetrics.sidebarGroupSpacing)
            }
            ForEach(group) { tab in
                tabRow(tab)
            }
        }
    }

    @ViewBuilder
    private var searchResultRows: some View {
        let results = searchResults
        if results.isEmpty {
            Text("No Results")
                .font(.dsBody)
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.horizontal, InterfaceMetrics.sidebarRowHorizontalPadding)
                .frame(height: InterfaceMetrics.sidebarRowHeight)
        } else {
            ForEach(SettingsTab.sidebarOrder) { tab in
                let entries = results.filter { $0.tab == tab }
                if !entries.isEmpty {
                    InterfaceSidebarGroupHeader(tab.title)
                    ForEach(entries.prefix(Self.searchResultsPerTab)) { entry in
                        InterfaceSidebarRow(entry.title, systemImage: tab.systemImage, tint: tab.tint, isSelected: false) {
                            open(entry)
                        }
                        .help("\(tab.title) › \(entry.title)")
                    }
                    if entries.count > Self.searchResultsPerTab {
                        InterfaceSidebarRow("\(entries.count - Self.searchResultsPerTab) More", systemImage: "ellipsis", tint: InterfaceSidebarTint.gray, isSelected: false) {
                            navigation.selectedTab = tab
                        }
                    }
                }
            }
        }
    }

    private var footerRows: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let missing = permissions.missingRequired {
                InterfaceSidebarRow("Permission Needed", systemImage: "exclamationmark.triangle", tint: InterfaceSidebarTint.orange, isSelected: false) {
                    permissions.request(missing)
                }
                .help("Upshot needs \(missing.title) access to capture.")
                .transition(.blurPop)
            }
            tabRow(SettingsTab.sidebarFooterTab)
        }
        .motion(value: permissions.missingRequired)
        .padding(.horizontal, Space.ml)
        .padding(.vertical, Space.ml)
    }

    private func tabRow(_ tab: SettingsTab) -> some View {
        InterfaceSidebarRow(tab.title, systemImage: tab.systemImage, tint: tab.tint, isSelected: navigation.selectedTab == tab) {
            isSidebarFocused = true
            navigation.selectedTab = tab
        }
    }

    private func open(_ entry: SettingsSearchEntry) {
        navigation.selectedTab = entry.tab
        AppLog.event("settings", "settings_search_result_opened", fields: ["tab": entry.tab.rawValue, "title": entry.title])
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        guard !isSearching else { return }
        let order = SettingsTab.sidebarOrder
        guard let index = order.firstIndex(of: navigation.selectedTab) else { return }
        switch direction {
        case .up where index > 0:
            navigation.selectedTab = order[index - 1]
        case .down where index < order.count - 1:
            navigation.selectedTab = order[index + 1]
        default:
            break
        }
    }
}

struct SettingsSearchEntry: Identifiable, Equatable {
    let title: String
    let tab: SettingsTab
    var keywords: String = ""

    var id: String { "\(tab.rawValue).\(title)" }

    static func matching(_ query: String) -> [SettingsSearchEntry] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return allEntries.filter { entry in
            let searchable = "\(entry.title) \(entry.tab.title) \(entry.keywords)"
            return words.allSatisfy { word in
                searchable.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    static let allEntries: [SettingsSearchEntry] = paneEntries + shortcutEntries

    private static let shortcutEntries: [SettingsSearchEntry] = CaptureHotkeyAction.allCases.map {
        SettingsSearchEntry(title: $0.title, tab: .shortcuts, keywords: "shortcut keyboard hotkey")
    }

    private static let paneEntries: [SettingsSearchEntry] = [
        SettingsSearchEntry(title: "Launch at login", tab: .general, keywords: "startup start open"),
        SettingsSearchEntry(title: "Show menu bar icon", tab: .general, keywords: "status item"),
        SettingsSearchEntry(title: "Show Dock icon", tab: .general, keywords: "hide app switcher"),
        SettingsSearchEntry(title: "Play sounds", tab: .general, keywords: "shutter audio"),
        SettingsSearchEntry(title: "Export folder", tab: .general, keywords: "save location directory"),
        SettingsSearchEntry(title: "Screen Recording", tab: .general, keywords: "permission privacy access allow"),
        SettingsSearchEntry(title: "Microphone", tab: .general, keywords: "permission privacy access allow"),
        SettingsSearchEntry(title: "Camera", tab: .general, keywords: "permission privacy access allow"),
        SettingsSearchEntry(title: "Position", tab: .quickAccess, keywords: "overlay screen edge"),
        SettingsSearchEntry(title: "Overlay size", tab: .quickAccess, keywords: "overlay"),
        SettingsSearchEntry(title: "Auto-close", tab: .quickAccess, keywords: "overlay dismiss"),
        SettingsSearchEntry(title: "Close after dragging", tab: .quickAccess, keywords: "overlay"),
        SettingsSearchEntry(title: "Close after uploading", tab: .quickAccess, keywords: "overlay cloud"),
        SettingsSearchEntry(title: "Swipe actions", tab: .quickAccess, keywords: "overlay gesture"),
        SettingsSearchEntry(title: "Card actions", tab: .quickAccess, keywords: "overlay buttons"),
        SettingsSearchEntry(title: "Save button", tab: .quickAccess, keywords: "save location export folder without asking"),
        SettingsSearchEntry(title: "Pinned screenshots", tab: .quickAccess, keywords: "pin corners shadow border"),
        SettingsSearchEntry(title: "File format", tab: .screenshots, keywords: "png jpeg heic compression"),
        SettingsSearchEntry(title: "Convert to sRGB", tab: .screenshots, keywords: "color profile"),
        SettingsSearchEntry(title: "Scale Retina screenshots to 1x", tab: .screenshots, keywords: "resolution"),
        SettingsSearchEntry(title: "Add a 1px border", tab: .screenshots, keywords: "outline"),
        SettingsSearchEntry(title: "Add @2x to Retina filenames", tab: .screenshots, keywords: "file name"),
        SettingsSearchEntry(title: "Screenshot filename", tab: .screenshots, keywords: "file name"),
        SettingsSearchEntry(title: "Show cursor in screenshots", tab: .screenshots, keywords: "pointer mouse"),
        SettingsSearchEntry(title: "Hide desktop icons while capturing", tab: .screenshots, keywords: "wallpaper"),
        SettingsSearchEntry(title: "Freeze screen during selection", tab: .screenshots, keywords: "area"),
        SettingsSearchEntry(title: "Show crosshair", tab: .screenshots, keywords: "area selection"),
        SettingsSearchEntry(title: "Show pixel magnifier", tab: .screenshots, keywords: "area selection zoom"),
        SettingsSearchEntry(title: "Window screenshot background", tab: .screenshots, keywords: "wallpaper padding shadow"),
        SettingsSearchEntry(title: "Include floating Upshot UI in captures", tab: .screenshots, keywords: "windows visibility"),
        SettingsSearchEntry(title: "After capture", tab: .screenshots, keywords: "copy save upload open"),
        SettingsSearchEntry(title: "Dim the screen outside the recorded area", tab: .screenRecording, keywords: "video"),
        SettingsSearchEntry(title: "Enable Do Not Disturb", tab: .screenRecording, keywords: "notifications focus"),
        SettingsSearchEntry(title: "Countdown", tab: .screenRecording, keywords: "timer video"),
        SettingsSearchEntry(title: "Cursor and clicks", tab: .screenRecording, keywords: "pointer highlight video"),
        SettingsSearchEntry(title: "Capture typed keys in future recordings", tab: .screenRecording, keywords: "keystrokes"),
        SettingsSearchEntry(title: "Video frame rate", tab: .screenRecording, keywords: "fps resolution"),
        SettingsSearchEntry(title: "Audio", tab: .screenRecording, keywords: "microphone system sound mono"),
        SettingsSearchEntry(title: "GIF", tab: .screenRecording, keywords: "animated frame rate quality"),
        SettingsSearchEntry(title: "After recording", tab: .screenRecording, keywords: "export reveal finder"),
        SettingsSearchEntry(title: "Keep editor above other windows", tab: .annotate, keywords: "always on top"),
        SettingsSearchEntry(title: "Draw shadows on new annotations", tab: .annotate, keywords: "shadow"),
        SettingsSearchEntry(title: "Expand canvas beyond the image edge", tab: .annotate, keywords: "canvas"),
        SettingsSearchEntry(title: "Recognition language", tab: .textRecognition, keywords: "ocr"),
        SettingsSearchEntry(title: "Keep line breaks", tab: .textRecognition, keywords: "ocr"),
        SettingsSearchEntry(title: "Detect links", tab: .textRecognition, keywords: "ocr url"),
        SettingsSearchEntry(title: "Detect QR codes and barcodes after capture", tab: .textRecognition, keywords: "ocr scan"),
        SettingsSearchEntry(title: "Cloudflare upload", tab: .cloud, keywords: "share link worker deploy"),
        SettingsSearchEntry(title: "Allow AI agents", tab: .mcp, keywords: "mcp server agent client"),
        SettingsSearchEntry(title: "Keep capture history", tab: .advanced, keywords: "retention days delete trash"),
        SettingsSearchEntry(title: "Open Capture History", tab: .advanced, keywords: "history"),
        SettingsSearchEntry(title: "Configuration file", tab: .advanced, keywords: "config toml reveal reload"),
        SettingsSearchEntry(title: "Analyze captures", tab: .textRecognition, keywords: "library text analysis search categories"),
        SettingsSearchEntry(title: "Sort existing captures", tab: .textRecognition, keywords: "library categories apple intelligence"),
        SettingsSearchEntry(title: "Updates", tab: .about, keywords: "version sparkle check")
    ]
}

private struct SettingsDetailView: View {
    let tab: SettingsTab
    let renderDetail: AnyView?

    var body: some View {
        Group {
            if let renderDetail {
                renderDetail
            } else {
                pane
            }
        }
        .navigationTitle(tab.title)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var pane: some View {
        Group {
            switch tab {
            case .general:
                SettingsGeneralPane()
            case .shortcuts:
                SettingsShortcutsPane()
            case .quickAccess:
                SettingsQuickAccessPane()
            case .screenshots:
                ScreenshotsSettingsPane()
            case .screenRecording:
                SettingsScreenRecordingPane()
            case .annotate:
                SettingsAnnotatePane()
            case .textRecognition:
                SettingsTextRecognitionPane()
            case .cloud:
                CloudSettingsPane()
            case .mcp:
                MCPSettingsPane()
            case .advanced:
                SettingsAdvancedPane()
            case .about:
                SettingsAboutPane()
            }
        }
    }
}

extension URL {
    var abbreviatedPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
