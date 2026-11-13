import SwiftUI

struct CaptureHistoryView: View {
    @Bindable var model: CaptureHistoryModel
    @State private var history = ScreenshotHistoryStore.shared
    @State private var projects = RecordingProjectStore.shared

    var body: some View {
        CaptureHistoryStrip(
            filter: $model.filter,
            selectedID: $model.selectedID,
            items: model.visibleItems,
            isLoading: model.isLoading,
            errorMessage: model.errorMessage,
            restore: { model.restoreSelection() },
            close: { CaptureHistoryPresenter.shared.dismiss() }
        )
        .onChange(of: history.items) { _, _ in model.refresh() }
        .onChange(of: projects.projects) { _, _ in model.refresh() }
    }
}

struct CaptureHistoryStrip: View {
    @Binding var filter: CaptureHistoryFilter
    @Binding var selectedID: String?
    let items: [CaptureLibraryItem]
    let isLoading: Bool
    let errorMessage: String?
    let restore: () -> Void
    let close: () -> Void

    static let thumbnailSize = CGSize(width: 192, height: 120)
    static let screenMargin = Space.m
    static let headerHeight: CGFloat = 40
    static let capturesHeight = thumbnailSize.height + InterfaceMetrics.controlHeight + Space.m + Space.s * 2
    static let preferredHeight = screenMargin * 2 + InterfaceMetrics.floatingPanelPadding * 2 + headerHeight + Space.s + capturesHeight + Space.s

    private static let filterOptions = CaptureHistoryFilter.allCases.map {
        InterfaceModeSwitchOption(value: $0, title: $0.title)
    }

    var body: some View {
        VStack(spacing: Space.s) {
            header
            captures
        }
        .padding(InterfaceMetrics.floatingPanelPadding)
        .frame(maxWidth: .infinity)
        .interfacePanelSurface(.panel)
        .padding(Self.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture History")
    }

    private var header: some View {
        ZStack {
            InterfaceModeSwitch("Capture Type", selection: $filter, options: Self.filterOptions, surface: .floating)
            HStack(spacing: 0) {
                if errorMessage != nil {
                    InterfaceToast(
                        "Restore Failed",
                        detail: "The file may have moved or become unreadable.",
                        systemImage: "exclamationmark.triangle.fill",
                        tone: .failure
                    )
                    .help(errorMessage ?? "")
                }
                Spacer(minLength: 0)
                InterfaceToolbarButton("Close", systemImage: "xmark", labelPlacement: .hidden, action: close)
            }
        }
        .frame(height: Self.headerHeight)
    }

    private var captures: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: Space.xxl) {
                    ForEach(items) { item in
                        CaptureHistoryCard(
                            item: item,
                            isSelected: selectedID == item.id,
                            select: { selectedID = item.id },
                            restore: restore
                        )
                        .id(item.id)
                    }
                }
                .padding(.horizontal, Space.xl)
                .padding(.vertical, Space.s)
            }
            .frame(height: Self.capturesHeight)
            .overlay {
                if items.isEmpty {
                    placeholder
                }
            }
            .onChange(of: selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .padding(.bottom, Space.s)
    }

    @ViewBuilder
    private var placeholder: some View {
        if isLoading {
            ProgressView()
                .accessibilityLabel("Loading Captures")
        } else {
            VStack(spacing: Space.m) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: IconSize.toolbar, weight: .regular))
                Text(filter == .all ? "No Captures" : "No \(filter.title)")
                    .font(.dsBodyEmphasis)
            }
            .foregroundStyle(Palette.secondaryLabel)
        }
    }
}

private struct CaptureHistoryCard: View {
    let item: CaptureLibraryItem
    let isSelected: Bool
    let select: () -> Void
    let restore: () -> Void

    var body: some View {
        VStack(spacing: Space.m) {
            Button(action: select) {
                InterfaceCard(isSelected: isSelected, padding: 0) {
                    CaptureLibraryThumbnail(item: item)
                        .frame(width: CaptureHistoryStrip.thumbnailSize.width, height: CaptureHistoryStrip.thumbnailSize.height)
                }
            }
            .buttonStyle(.plain)
            .help(item.name)
            .accessibilityLabel("\(item.name), \(CaptureHistoryFilter.kindTitle(for: item)), \(relativeTime)")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            Group {
                if isSelected {
                    Button("Restore", systemImage: "arrow.uturn.backward", action: restore)
                        .buttonStyle(.interfaceAction)
                        .help("Restore to Quick Access (Return)")
                } else {
                    HStack(spacing: Space.xs) {
                        Image(systemName: kindSymbol)
                            .font(.system(size: IconSize.segment, weight: .regular))
                        Text(relativeTime)
                            .font(.dsBody)
                            .lineLimit(1)
                    }
                    .foregroundStyle(Palette.secondaryLabel)
                    .accessibilityHidden(true)
                }
            }
            .frame(height: InterfaceMetrics.controlHeight)
        }
        .frame(width: CaptureHistoryStrip.thumbnailSize.width)
    }

    private var relativeTime: String {
        item.createdAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }

    private var kindSymbol: String {
        if item.session != nil { return "film" }
        if item.fileURL.pathExtension.lowercased() == "gif" { return "photo.stack" }
        return item.isVideo ? "video.fill" : "photo"
    }
}
