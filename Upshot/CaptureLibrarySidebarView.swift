import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CaptureLibrarySidebarView: View {
    @Bindable var model: CaptureLibraryModel
    let showsCategories: Bool
    let updateVersion: String?
    @Binding var categoriesExpanded: Bool
    @Binding var appsExpanded: Bool

    @FocusState private var isSearchFocused: Bool
    @FocusState private var areRowsFocused: Bool

    private static let bottomFadeHeight = Space.xxxl

    private var scope: CaptureLibraryScope { model.scope ?? .kind(.all) }

    private var navigableScopes: [CaptureLibraryScope] {
        var scopes = CaptureLibraryFilter.allCases.map { CaptureLibraryScope.kind($0) }
        if showsCategories, categoriesExpanded { scopes += model.categoryFacets.map { .category($0.category) } }
        if appsExpanded { scopes += model.appFacets.map { .app($0.id) } }
        return scopes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            InterfaceSidebarSearchField(prompt: "Search Apps and Text", text: $model.searchText)
                .focused($isSearchFocused)
                .padding(.horizontal, Space.ml)
                .padding(.bottom, Space.m)
                .background {
                    Button("Find") { isSearchFocused = true }
                        .keyboardShortcut("f", modifiers: .command)
                        .hidden()
                }
            InterfaceSidebar {
                InterfaceSidebarGroupHeader("Library")
                ForEach(CaptureLibraryFilter.allCases) { filter in
                    row(filter.title, icon: .symbol(filter.symbol, tint: filter.sidebarTint), count: model.count(for: filter), scope: .kind(filter))
                }
                if showsCategories, !model.categoryFacets.isEmpty {
                    CaptureLibrarySidebarGroupToggle(title: "Categories", isExpanded: $categoriesExpanded)
                    if categoriesExpanded {
                        ForEach(model.categoryFacets, id: \.category) { facet in
                            row(facet.category.title, icon: .symbol(facet.category.symbol, tint: facet.category.sidebarTint), count: facet.count, scope: .category(facet.category))
                        }
                    }
                }
                if !model.appFacets.isEmpty {
                    CaptureLibrarySidebarGroupToggle(title: "Apps", isExpanded: $appsExpanded)
                    if appsExpanded {
                        ForEach(model.appFacets) { app in
                            row(app.name, icon: .image(LibraryAppIcons.icon(for: app.bundleIdentifier)), count: app.count, scope: .app(app.id))
                        }
                    }
                }
            }
            .contentMargins(.bottom, Self.bottomFadeHeight, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: Self.bottomFadeHeight)
                }
            }
            .focusable()
            .focused($areRowsFocused)
            .focusEffectDisabled()
            .onMoveCommand(perform: moveSelection)
            CaptureLibrarySidebarFooter(updateVersion: updateVersion)
        }
    }

    private func row(_ title: String, icon: InterfaceSidebarIcon, count: Int, scope rowScope: CaptureLibraryScope) -> some View {
        InterfaceSidebarRow(title, icon: icon, count: count, isSelected: scope == rowScope) {
            model.scope = rowScope
            areRowsFocused = true
            AppLog.event("library", "sidebar_scope_selected", fields: ["input": "pointer", "scope": String(describing: rowScope)])
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let scopes = navigableScopes
        guard let current = scopes.firstIndex(of: scope) else {
            model.scope = scopes.first
            return
        }
        switch direction {
        case .up where current > 0: model.scope = scopes[current - 1]
        case .down where current < scopes.count - 1: model.scope = scopes[current + 1]
        default: break
        }
        AppLog.event("library", "sidebar_scope_selected", fields: ["input": "keyboard", "scope": String(describing: model.scope ?? .kind(.all))])
    }
}

private struct CaptureLibrarySidebarGroupToggle: View {
    let title: String
    @Binding var isExpanded: Bool

    @State private var isHovering = false

    var body: some View {
        Button {
            isExpanded.toggle()
            AppLog.event("library", "sidebar_group_toggled", fields: ["expanded": String(isExpanded), "group": title])
        } label: {
            HStack(spacing: Space.xs) {
                InterfaceSidebarGroupHeader(title)
                Spacer(minLength: 0)
                Image(systemName: "chevron.down")
                    .font(.system(size: IconSize.disclosureChevron, weight: .semibold))
                    .foregroundStyle(Palette.secondaryLabel)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
                    .opacity(isHovering || !isExpanded ? 1 : 0)
                    .padding(.top, InterfaceMetrics.sidebarGroupSpacing)
                    .padding(.bottom, Space.xs)
                    .padding(.trailing, InterfaceMetrics.sidebarRowHorizontalPadding)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(isExpanded ? "Hide \(title)" : "Show \(title)")
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
    }
}

private struct CaptureLibrarySidebarFooter: View {
    let updateVersion: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let updateVersion {
                InterfaceSidebarRow("Update to \(updateVersion)", systemImage: "arrow.down", tint: InterfaceSidebarTint.blue, isSelected: false) {
                    UpdaterManager.shared.checkForUpdates()
                }
                .help("Download Upshot \(updateVersion)")
                .transition(.opacity)
            }
            InterfaceSidebarRow("Settings", systemImage: "gearshape", tint: InterfaceSidebarTint.gray, isSelected: false) {
                SettingsWindowController.show(tab: .general)
            }
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, Space.ml)
        .padding(.bottom, Space.ml)
        .animation(.morphIfAllowed, value: updateVersion)
    }
}

extension CaptureLibraryFilter {
    var sidebarTint: Color {
        switch self {
        case .all: InterfaceSidebarTint.indigo
        case .screenshots: InterfaceSidebarTint.blue
        case .recordings: InterfaceSidebarTint.red
        }
    }
}

extension CaptureCategory {
    var sidebarTint: Color {
        switch self {
        case .code: InterfaceSidebarTint.gray
        case .design: InterfaceSidebarTint.pink
        case .website: InterfaceSidebarTint.blue
        case .document: InterfaceSidebarTint.indigo
        case .chat: InterfaceSidebarTint.green
        case .email: InterfaceSidebarTint.blue
        case .data: InterfaceSidebarTint.teal
        case .error: InterfaceSidebarTint.red
        case .receipt: InterfaceSidebarTint.orange
        case .social: InterfaceSidebarTint.purple
        case .media: InterfaceSidebarTint.yellow
        case .settings: InterfaceSidebarTint.gray
        case .other: InterfaceSidebarTint.gray
        }
    }
}

@MainActor
enum LibraryAppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleIdentifier: String?) -> NSImage {
        let key = bundleIdentifier ?? ""
        if let icon = cache[key] { return icon }
        let icon = bundleIdentifier
            .flatMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSWorkspace.shared.icon(for: .application)
        cache[key] = icon
        return icon
    }
}
