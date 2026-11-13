import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureLibraryWindow: View {
    @State private var isOpen = true
    @State private var window: NSWindow?

    var body: some View {
        Group {
            if isOpen { CaptureLibraryView() } else { Color.clear }
        }
        .onAppear { isOpen = true }
        .onWindowChange { window = $0 }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            guard let closing = notification.object as? NSWindow, closing === window else { return }
            isOpen = false
            Task { await CaptureLibraryThumbnails.shared.removeAll() }
        }
    }
}

struct CaptureLibraryView: View {
    var presentedUpdateVersion: String? = nil

    @State private var model = CaptureLibraryModel.shared
    @State private var history = ScreenshotHistoryStore.shared
    @State private var projects = RecordingProjectStore.shared
    @State private var index = CaptureLibraryIndex.shared
    @ObservedObject private var updater = UpdaterManager.shared
    @State private var libraryWindow: NSWindow?
    @State private var hasBecomeKey = false
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic
    @AppStorage("captureLibrary.layout") private var layout: CaptureLibraryLayout = .grid
    @AppStorage("captureLibrary.inspectorVisible") private var inspectorVisible = true
    @AppStorage("captureLibrary.sort") private var savedSort: CaptureLibrarySort = .newest
    @AppStorage("captureLibrary.categoriesExpanded") private var categoriesExpanded = true
    @AppStorage("captureLibrary.appsExpanded") private var appsExpanded = true
    @AppStorage(UpshotPreferences.libraryAnalyzeCapturesKey) private var analyzeCaptures = true
    @AppStorage(UpshotPreferences.librarySortExistingKey) private var sortExisting = false
    @AppStorage(UpshotPreferences.librarySortOfferDismissedKey) private var sortOfferDismissed = false

    private var scope: CaptureLibraryScope { model.scope ?? .kind(.all) }

    private var showsSortOffer: Bool {
        analyzeCaptures && !sortExisting && !sortOfferDismissed && index.unsortedExistingCount > 0
    }

    private var scopeTitle: String {
        switch scope {
        case .kind(let filter): filter.title
        case .category(let category): category.title
        case .app(let key): model.appFacets.first { $0.id == key }?.name ?? "App"
        }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            CaptureLibrarySidebarView(
                model: model,
                showsCategories: analyzeCaptures,
                updateVersion: updater.availableUpdateVersion ?? presentedUpdateVersion,
                categoriesExpanded: $categoriesExpanded,
                appsExpanded: $appsExpanded
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: InterfaceMetrics.sidebarWidth, max: 280)
        } detail: {
            VStack(spacing: 0) {
                if showsSortOffer {
                    CaptureLibrarySortOffer(count: index.unsortedExistingCount) {
                        index.sortExistingCaptures()
                    } onDismiss: {
                        sortOfferDismissed = true
                    }
                    .transition(.opacity)
                    Divider()
                }
                CaptureLibraryBrowser(model: model, layout: layout, scope: scope, scopeTitle: scopeTitle)
                Divider()
                CaptureLibraryStatusBar(model: model, index: index)
            }
            .navigationTitle(scopeTitle)
            .navigationSubtitle("Upshot")
        }
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: $inspectorVisible) {
            GeometryReader { _ in
                CaptureLibraryInspector(model: model)
            }
            .inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .toolbar {
            CaptureLibraryToolbar(model: model, layout: $layout, inspectorVisible: $inspectorVisible)
        }
        .frame(minWidth: 860, minHeight: 540)
        .onAppear {
            guard !UpshotStorage.isRenderingStates else { return }
            AppActivationPolicy.enter()
            CaptureLibraryIndex.shared.start()
            model.windowDidOpen()
            UpdaterManager.shared.checkForUpdateInformation()
            model.sortOrder = savedSort
            model.refresh()
        }
        .onDisappear {
            AppActivationPolicy.leave()
            model.windowDidClose()
        }
        .onWindowChange { window in
            libraryWindow = window
            Task { resignInitialTextFocus(in: window) }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow, window === libraryWindow else { return }
            model.refresh()
            if !hasBecomeKey {
                hasBecomeKey = true
                resignInitialTextFocus(in: window)
            }
        }
        .onChange(of: history.items) { _, _ in model.refresh() }
        .onChange(of: projects.projects) { _, _ in model.refresh() }
        .onChange(of: model.sortOrder) { _, value in savedSort = value }
        .onChange(of: analyzeCaptures) { _, enabled in
            if !enabled, case .category = scope { model.scope = .kind(.all) }
        }
        .animation(.morphIfAllowed, value: showsSortOffer)
        .alert("Rename Capture", isPresented: Binding(
            get: { model.renamingItem != nil },
            set: { if !$0 { model.renamingItem = nil } }
        )) {
            TextField("Name", text: $model.renameText)
            Button("Rename") { model.rename() }
                .disabled(model.renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Cancel", role: .cancel) { model.renamingItem = nil }
        }
        .alert("Move \(model.pendingTrash.count == 1 ? "capture" : "\(model.pendingTrash.count) captures") to Trash?", isPresented: Binding(
            get: { !model.pendingTrash.isEmpty },
            set: { if !$0 { model.pendingTrash = [] } }
        )) {
            Button("Move to Trash", role: .destructive) { model.movePendingItemsToTrash() }
            Button("Cancel", role: .cancel) { model.pendingTrash = [] }
        } message: {
            Text("The local files and their edits will move to Trash. Exported copies and cloud links will remain available.")
        }
        .alert("The Library action could not be completed", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
    }

    private func resignInitialTextFocus(in window: NSWindow?) {
        guard let window, window.firstResponder is NSText else { return }
        window.makeFirstResponder(nil)
        AppLog.event("library", "initial_text_focus_resigned", fields: ["outcome": "resigned"])
    }
}

private struct CaptureLibraryToolbar: ToolbarContent {
    @Bindable var model: CaptureLibraryModel
    @Binding var layout: CaptureLibraryLayout
    @Binding var inspectorVisible: Bool

    var body: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button("Capture Fullscreen", systemImage: "macwindow") { CaptureCoordinator.shared.captureFullscreen() }
                Button("Capture Window", systemImage: "macwindow.on.rectangle") { CaptureCoordinator.shared.captureWindow() }
                Button("Capture Area", systemImage: "rectangle.dashed") { CaptureCoordinator.shared.captureArea() }
                Divider()
                Button("Record Screen", systemImage: "record.circle") { RecordingPickerPresenter.shared.show() }
                    .disabled(ScreenRecordingManager.shared.isActive)
            } label: { Label("New Capture", systemImage: "plus") }
            .menuIndicator(.hidden)
            .help("New capture")
        }
        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: $layout) {
                Label("Grid View", systemImage: "square.grid.2x2").tag(CaptureLibraryLayout.grid).help("Grid view")
                Label("List View", systemImage: "list.bullet").tag(CaptureLibraryLayout.list).help("List view")
            }
            .labelStyle(.iconOnly)
            .pickerStyle(.segmented)
            .help("Switch between grid and list")
        }
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: $model.sortOrder) {
                    ForEach(CaptureLibrarySort.allCases) { Text($0.title).tag($0) }
                }
                Divider()
                Button("Refresh", systemImage: "arrow.clockwise") { model.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            } label: { Label("Sort", systemImage: "arrow.up.arrow.down") }
            .menuIndicator(.hidden)
            .help("Sort captures")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { withAnimation(.morphIfAllowed) { inspectorVisible.toggle() } } label: {
                Label(inspectorVisible ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.right")
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .help(inspectorVisible ? "Hide Inspector" : "Show Inspector")
        }
    }
}

private struct CaptureLibraryBrowser: View {
    @Bindable var model: CaptureLibraryModel
    let layout: CaptureLibraryLayout
    let scope: CaptureLibraryScope
    let scopeTitle: String

    private var activeFilter: CaptureLibraryFilter {
        if case .kind(let filter) = scope { filter } else { .all }
    }

    var body: some View {
        if model.items.isEmpty && model.isLoading {
            ProgressView().controlSize(.regular).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.visibleItems.isEmpty {
            if !model.searchText.isEmpty {
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: "No Results",
                    message: "Nothing in \(scopeTitle) matches “\(model.searchText)”."
                ) {
                    InterfaceActionButton("Clear Search") { model.searchText = "" }
                }
            } else if scope != .kind(activeFilter) {
                EmptyStateView(
                    systemImage: "square.dashed",
                    title: "No Captures in \(scopeTitle)",
                    message: "Captures filed under \(scopeTitle) appear here."
                )
            } else {
                EmptyStateView(
                    systemImage: activeFilter.symbol,
                    title: "No \(activeFilter == .all ? "Captures" : activeFilter.title) Yet",
                    message: emptyLibraryMessage
                ) {
                    if activeFilter != .recordings {
                        InterfaceActionButton("Capture Area", systemImage: "rectangle.dashed") {
                            CaptureCoordinator.shared.captureArea()
                        }
                    }
                    if activeFilter != .screenshots {
                        InterfaceActionButton("Record Screen", systemImage: "record.circle") {
                            RecordingPickerPresenter.shared.show()
                        }
                        .disabled(ScreenRecordingManager.shared.isActive)
                    }
                }
            }
        } else {
            CaptureLibraryCollection(items: model.visibleItems, revision: model.contentRevision, layout: layout,
                searchTokens: model.searchTokens, selection: $model.selection, isBusy: model.isBusy, onAction: model.perform)
        }
    }

    private var emptyLibraryMessage: String {
        switch activeFilter {
        case .all: "Screenshots and recordings appear here."
        case .screenshots: "Screenshots appear here."
        case .recordings: "Recordings appear here as editable projects."
        }
    }
}

private struct CaptureLibraryStatusBar: View {
    let model: CaptureLibraryModel
    let index: CaptureLibraryIndex

    var body: some View {
        HStack(spacing: Space.m) {
            if let title = model.operationTitle {
                if let id = model.uploadingItemID,
                   let progress = CloudUploader.shared.uploadProgress[id] {
                    ProgressView(value: min(progress, 0.99))
                        .progressViewStyle(.linear)
                        .frame(width: 120)
                        .accessibilityLabel("Upload progress")
                    Text(progress >= 0.99 ? "Finishing upload…" : title)
                    Text(min(progress, 0.99), format: .percent.precision(.fractionLength(0)).rounded(rule: .down))
                        .foregroundStyle(Palette.label)
                } else {
                    ProgressView().controlSize(.mini)
                    Text(title)
                }
            } else {
                Text("\(model.visibleItems.count) \(model.visibleItems.count == 1 ? "capture" : "captures")")
                if !model.selection.isEmpty { Text("· \(model.selection.count) selected") }
            }
            Spacer()
            if index.pendingCount > 0 {
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.mini)
                    if index.readingCount > 0 {
                        Text("Reading text in \(index.readingCount) \(index.readingCount == 1 ? "capture" : "captures")")
                    } else {
                        Text("Sorting \(index.sortingCount) \(index.sortingCount == 1 ? "capture" : "captures")")
                    }
                }
                .help("Upshot reads the text in each capture so search can find it, then sorts it into a category. All on this Mac.")
            } else if model.isLoading {
                ProgressView().controlSize(.mini).help("Refreshing Library")
            }
        }
        .font(.dsCaption.monospacedDigit())
        .foregroundStyle(Palette.secondaryLabel)
        .padding(.horizontal, Space.xl)
        .frame(height: Space.xxxl)
    }
}

private struct CaptureLibrarySortOffer: View {
    let count: Int
    let onAccept: () -> Void
    let onDismiss: () -> Void

    private var estimate: String {
        let minutes = max(5, (Double(count) * 1.3 / 60 / 5).rounded() * 5)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = minutes >= 60 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .full
        return formatter.string(from: minutes * 60) ?? "a while"
    }

    var body: some View {
        HStack(spacing: Space.l) {
            Image(systemName: "sparkles")
                .font(.system(size: IconSize.toast, weight: .medium))
                .foregroundStyle(Palette.secondaryLabel)
            InterfaceRowLabel(
                "Sort \(count.formatted()) older \(count == 1 ? "capture" : "captures") into categories?",
                detail: "Apple Intelligence on this Mac, about \(estimate)."
            )
            .frame(minWidth: 160, alignment: .leading)
            Spacer(minLength: Space.l)
            InterfaceActionButton("Not Now", action: onDismiss)
            InterfaceActionButton("Sort Captures", action: onAccept)
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.ml)
    }
}
