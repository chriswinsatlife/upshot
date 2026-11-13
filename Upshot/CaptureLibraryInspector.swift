import AppKit
import SwiftUI

struct CaptureLibraryInspector: View {
    let model: CaptureLibraryModel

    @State private var byteCount: Int64?
    @State private var pendingCloudDelete: CaptureLibraryItem?
    @State private var similar: [CaptureLibraryItem] = []

    private var items: [CaptureLibraryItem] { model.selectedItems }
    private var index: CaptureLibraryIndex { .shared }

    private var sizeText: String {
        byteCount.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "Calculating…"
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyStateView(
                    systemImage: "photo.on.rectangle.angled",
                    title: "No Selection",
                    message: "Select a capture to see its details."
                )
                .transition(.opacity)
            } else {
                InterfaceFormPage {
                    if items.count == 1, let item = items.first {
                        CaptureLibraryInspectorDetails(model: model, item: item, sizeText: sizeText)
                        CaptureLibraryInspectorText(model: model, itemID: item.id)
                        CaptureLibraryInspectorSimilar(model: model, similar: similar)
                    } else {
                        CaptureLibraryInspectorSelection(items: items, sizeText: sizeText)
                    }
                }
                .scrollEdgeEffectSoftIfAvailable()
                .transition(.opacity)
            }
        }
        .safeAreaBarIfAvailable(edge: .bottom) {
            if !items.isEmpty {
                CaptureLibraryInspectorActions(model: model, items: items, pendingCloudDelete: $pendingCloudDelete)
                    .transition(.opacity)
            }
        }
        .motion(.morph, value: items.isEmpty)
        .task(id: similarityKey) {
            guard items.count == 1, let item = items.first else { similar = []; return }
            let ids = await index.similar(to: item.id, among: model.items.map(\.id), limit: 9)
            guard !Task.isCancelled else { return }
            similar = ids.compactMap(model.item(id:))
        }
        .task(id: items.map(\.thumbnailKey)) {
            byteCount = nil
            let urls = items.map(\.ownedURL)
            let scan = Task.detached(priority: .utility) {
                urls.reduce(Int64(0)) { total, url in
                    Task.isCancelled ? total : total + CaptureLibraryScanner.sizeOnDisk(of: url)
                }
            }
            let size = await withTaskCancellationHandler { await scan.value } onCancel: { scan.cancel() }
            guard !Task.isCancelled else { return }
            byteCount = size
        }
        .alert("Delete from cloud?", isPresented: Binding(
            get: { pendingCloudDelete != nil }, set: { if !$0 { pendingCloudDelete = nil } }
        ), presenting: pendingCloudDelete) { item in
            Button("Delete", role: .destructive) {
                model.deleteCloudCopy(item)
                pendingCloudDelete = nil
            }
            Button("Cancel", role: .cancel) { pendingCloudDelete = nil }
        } message: { _ in
            Text("This permanently removes the cloud copy and breaks its share link. Your local capture stays in the Library.")
        }
    }

    private var similarityKey: String {
        guard items.count == 1, let item = items.first else { return "" }
        return "\(item.id)|\(index.analyses[item.id]?.hasFeaturePrint == true)|\(model.items.count)"
    }
}

private struct CaptureLibraryInspectorDetails: View {
    let model: CaptureLibraryModel
    let item: CaptureLibraryItem
    let sizeText: String

    var body: some View {
        Section {
            CaptureLibraryInspectorValueRow("Dimensions", value: item.dimensions)
            if item.isVideo { CaptureLibraryInspectorValueRow("Duration", value: item.durationText) }
            CaptureLibraryInspectorValueRow("Size on Disk", value: sizeText)
            CaptureLibraryInspectorValueRow("Created", value: item.createdAt.formatted(date: .numeric, time: .shortened))
            if item.modifiedAt.timeIntervalSince(item.createdAt) >= 60 {
                CaptureLibraryInspectorValueRow("Modified", value: item.modifiedAt.formatted(date: .numeric, time: .shortened))
            }
            if let source = item.source {
                InterfaceRow("App") {
                    Button {
                        model.searchText = ""
                        model.scope = .app(source.appKey)
                    } label: {
                        Label {
                            Text(source.appName)
                        } icon: {
                            Image(nsImage: LibraryAppIcons.icon(for: source.bundleIdentifier))
                                .resizable()
                                .frame(width: IconSize.toast, height: IconSize.toast)
                        }
                    }
                    .help("Show all captures from \(source.appName)")
                }
                if let window = source.windowTitle {
                    CaptureLibraryInspectorValueRow("Window", value: window)
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: Space.xl) {
                CaptureLibraryInspectorPreview(model: model, item: item)
                CaptureLibraryInspectorTitle(model: model, item: item)
                InterfaceSectionHeader("Information")
            }
        }
    }
}

private struct CaptureLibraryInspectorValueRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        InterfaceRow(title) {
            Text(value)
                .font(.dsBody.monospacedDigit())
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .textSelection(.enabled)
                .contentTransition(.numericText())
                .layoutPriority(1)
        }
    }
}

private struct CaptureLibraryInspectorPreview: View {
    let model: CaptureLibraryModel
    let item: CaptureLibraryItem

    private var previewAspectRatio: CGFloat {
        guard item.pixelWidth > 0, item.pixelHeight > 0 else { return 1.6 }
        return min(max(CGFloat(item.pixelWidth) / CGFloat(item.pixelHeight), 0.75), 2.4)
    }

    var body: some View {
        Button { model.perform(.preview) } label: {
            CaptureLibraryThumbnail(item: item)
                .aspectRatio(previewAspectRatio, contentMode: .fit)
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                .hairline(radius: Radius.card)
                .contentShape(.rect(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isBusy)
        .accessibilityLabel("Quick Look \(item.name)")
        .help("Quick Look (Space)")
    }
}

private struct CaptureLibraryInspectorTitle: View {
    let model: CaptureLibraryModel
    let item: CaptureLibraryItem

    var body: some View {
        let analysis = CaptureLibraryIndex.shared.analyses[item.id]
        let hasDefaultName = item.name == item.fileURL.lastPathComponent || item.name.hasPrefix("Upshot_")
        let headline = (hasDefaultName ? analysis?.title : nil) ?? item.name
        let secondary = headline == item.name ? analysis?.title : item.name
        VStack(alignment: .leading, spacing: Space.s) {
            Text(headline)
                .font(.dsTitle)
                .foregroundStyle(Palette.label)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(headline == item.name ? "" : "Described on this Mac by Apple Intelligence")
            if let secondary {
                Text(secondary)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            LibraryFlowLayout(spacing: Space.s) {
                if let category = analysis?.category, category != .other {
                    Button {
                        model.searchText = ""
                        model.scope = .category(category)
                    } label: {
                        Tag(text: category.title, systemImage: category.symbol)
                    }
                    .buttonStyle(.plain)
                    .help("Show all \(category.title)")
                }
                if item.isVideo {
                    Tag(text: item.kindTitle, systemImage: "film")
                }
                if item.hasDraft {
                    Tag(text: "Unsaved Edits", systemImage: "circle.lefthalf.filled", tint: Palette.warning)
                } else if item.hasEdits {
                    Tag(text: "Edited", systemImage: "slider.horizontal.3")
                }
                if item.cloudURL != nil {
                    Tag(text: "Shared", systemImage: "link")
                }
                ForEach(analysis?.keywords ?? [], id: \.self) { keyword in
                    Button { model.searchText = keyword } label: {
                        Tag(text: keyword)
                    }
                    .buttonStyle(.plain)
                    .help("Search for “\(keyword)”")
                }
            }
            .padding(.top, Space.xxs)
        }
        .textCase(nil)
    }
}

private struct CaptureLibraryInspectorText: View {
    let model: CaptureLibraryModel
    let itemID: String

    @State private var showsAllText = false

    private static let previewParagraphCount = 6

    var body: some View {
        let index = CaptureLibraryIndex.shared
        Group {
            if let analysis = index.analyses[itemID], analysis.version == CaptureAnalysis.currentVersion {
                let paragraphs = orderedParagraphs(analysis)
                if !paragraphs.isEmpty {
                    InterfaceSection("Text") {
                        VStack(alignment: .leading, spacing: Space.m) {
                            ForEach(Array(paragraphs.prefix(showsAllText ? paragraphs.count : Self.previewParagraphCount).enumerated()), id: \.offset) { _, paragraph in
                                Text(highlighted(paragraph))
                                    .font(paragraph.contains("\n") ? .system(size: 11, design: .monospaced) : .dsCallout)
                                    .foregroundStyle(Palette.label)
                                    .lineSpacing(Space.xxs)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .textSelection(.enabled)
                        .padding(.vertical, Space.xs)
                        HStack(spacing: Space.m) {
                            Button("Copy Text") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(analysis.text, forType: .string)
                            }
                            if paragraphs.count > Self.previewParagraphCount {
                                Button(showsAllText ? "Show Less" : "Show All Text") {
                                    withAnimation(.fold) { showsAllText.toggle() }
                                }
                            }
                        }
                    }
                }
            } else if index.pendingCount > 0 {
                InterfaceSection("Text") {
                    HStack(spacing: Space.s) {
                        ProgressView().controlSize(.mini)
                        Text("Reading text…")
                            .font(.dsBody)
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                    .frame(minHeight: InterfaceMetrics.rowMinimumHeight)
                }
            }
        }
        .onChange(of: itemID) { _, _ in showsAllText = false }
    }

    private func orderedParagraphs(_ analysis: CaptureAnalysis) -> [String] {
        var paragraphs = CaptureReadableText.paragraphs(from: analysis.lines)
        if paragraphs.isEmpty, let transcript = analysis.transcript { paragraphs = [transcript] }
        let tokens = model.searchTokens
        guard !tokens.isEmpty else { return paragraphs }
        let matching = paragraphs.filter { paragraph in
            let folded = CaptureLibrarySearch.fold(paragraph)
            return tokens.contains { folded.contains($0) }
        }
        return matching + paragraphs.filter { !matching.contains($0) }
    }

    private func highlighted(_ paragraph: String) -> AttributedString {
        var text = AttributedString(paragraph)
        for token in model.searchTokens {
            var searchStart = text.startIndex
            while searchStart < text.endIndex,
                  let range = text[searchStart...].range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                text[range].backgroundColor = Palette.highlight.opacity(0.22)
                text[range].foregroundColor = Palette.label
                searchStart = range.upperBound
            }
        }
        return text
    }
}

private struct CaptureLibraryInspectorSimilar: View {
    let model: CaptureLibraryModel
    let similar: [CaptureLibraryItem]

    var body: some View {
        if !similar.isEmpty {
            InterfaceSection("Similar") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.m), count: 3), spacing: Space.m) {
                    ForEach(similar) { match in
                        Button { model.reveal(match.id) } label: {
                            CaptureLibraryThumbnail(item: match)
                                .aspectRatio(1.3, contentMode: .fit)
                                .clipShape(.rect(cornerRadius: Radius.tile, style: .continuous))
                                .hairline(radius: Radius.tile, opacity: 0.08)
                        }
                        .buttonStyle(.plain)
                        .help(match.name)
                        .accessibilityLabel("Select \(match.name)")
                    }
                }
                .padding(.vertical, Space.xs)
            }
        }
    }
}

private struct CaptureLibraryInspectorSelection: View {
    let items: [CaptureLibraryItem]
    let sizeText: String

    var body: some View {
        Section {
            CaptureLibraryInspectorValueRow("Screenshots", value: "\(items.filter { !$0.isVideo }.count)")
            CaptureLibraryInspectorValueRow("Recordings", value: "\(items.filter(\.isVideo).count)")
            CaptureLibraryInspectorValueRow("Size on Disk", value: sizeText)
        } header: {
            VStack(alignment: .leading, spacing: Space.xl) {
                ZStack {
                    ForEach(Array(items.prefix(3).enumerated().reversed()), id: \.element.id) { index, item in
                        CaptureLibraryThumbnail(item: item)
                            .aspectRatio(1.45, contentMode: .fit)
                            .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
                            .hairline(radius: Radius.card)
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                            .scaleEffect(1 - CGFloat(index) * 0.06)
                            .rotationEffect(.degrees(Double(index) * (index.isMultiple(of: 2) ? 3.5 : -3.5)))
                            .offset(y: -CGFloat(index) * 8)
                    }
                }
                .padding(.top, Space.l)
                .padding(.horizontal, Space.m)
                .motion(value: items.count)
                Text("\(items.count) Captures")
                    .font(.dsTitle)
                    .foregroundStyle(Palette.label)
                    .contentTransition(.numericText())
                InterfaceSectionHeader("Selection")
            }
            .textCase(nil)
        }
    }
}

private struct CaptureLibraryInspectorActions: View {
    let model: CaptureLibraryModel
    let items: [CaptureLibraryItem]
    @Binding var pendingCloudDelete: CaptureLibraryItem?

    @State private var pendingCloudUpload: CaptureLibraryItem?
    @State private var copiedAction: CopiedAction?
    @State private var copiedResetTask: Task<Void, Never>?

    private enum CopiedAction { case capture, link }

    private var single: CaptureLibraryItem? { items.count == 1 ? items.first : nil }

    var body: some View {
        HStack(spacing: Space.m) {
            Button { model.perform(.edit) } label: {
                Label(single?.isVideo == true ? "Edit" : "Annotate", systemImage: single?.isVideo == true ? "film" : "pencil.tip.crop.circle")
            }
            .disabled(single == nil)

            Button {
                model.perform(.copy)
                confirm(.capture)
            } label: {
                Label(copiedAction == .capture ? "Copied" : "Copy", systemImage: copiedAction == .capture ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .help(copiedAction == .capture ? "Copied" : "Copy (⌘C)")

            if CloudUploader.shared.isConfigured || items.contains(where: { $0.cloudURL != nil }) {
                cloudButton
            }

            Spacer(minLength: 0)

            Menu {
                Button("Export…", systemImage: "square.and.arrow.up") { model.perform(.export) }
                if single != nil {
                    Button("Rename…", systemImage: "pencil") { model.perform(.rename) }
                }
                Button("Reveal in Finder", systemImage: "folder") { model.perform(.reveal) }
                if let item = single, let link = item.cloudURL {
                    Divider()
                    if let url = URL(string: link) {
                        Link(destination: url) { Label("Open Shared Capture", systemImage: "arrow.up.right") }
                    }
                    Button("Delete from Cloud…", systemImage: "icloud.slash", role: .destructive) {
                        pendingCloudDelete = item
                    }
                }
                Divider()
                Button("Move to Trash…", systemImage: "trash", role: .destructive) { model.perform(.trash) }
            } label: {
                Label("More Actions", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More Actions")
            .accessibilityLabel("More capture actions")
        }
        .buttonStyle(.interfaceAction)
        .padding(.horizontal, Space.xl)
        .padding(.top, Space.ml)
        .padding(.bottom, Space.xl)
        .disabled(model.isBusy)
        .onChange(of: items.map(\.id)) { _, _ in pendingCloudUpload = nil }
        .onDisappear { copiedResetTask?.cancel() }
    }

    @ViewBuilder
    private var cloudButton: some View {
        if let item = single, item.cloudURL != nil {
            Button {
                model.copyLink(item)
                confirm(.link)
            } label: {
                Label(copiedAction == .link ? "Copied" : "Copy Cloud Link", systemImage: copiedAction == .link ? "checkmark" : "link")
                    .labelStyle(.iconOnly)
            }
            .help(copiedAction == .link ? "Copied" : "Copy Cloud Link")
        } else {
            Button {
                pendingCloudUpload = single
            } label: {
                Label("Share to Cloud", systemImage: "icloud.and.arrow.up")
                    .labelStyle(.iconOnly)
            }
            .help("Share to Cloud")
            .disabled(single == nil)
            .popover(item: $pendingCloudUpload, arrowEdge: .top) { item in
                CloudUploadOptionsPopover(suggestedTitle: item.name) { options in
                    model.upload(item, options: options)
                }
            }
        }
    }

    private func confirm(_ action: CopiedAction) {
        copiedAction = action
        copiedResetTask?.cancel()
        copiedResetTask = Task {
            try? await Task.sleep(for: .seconds(1.4))
            guard !Task.isCancelled else { return }
            copiedAction = nil
        }
    }
}

struct LibraryFlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func rows(width: CGFloat, subviews: Subviews) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + size.width <= width {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].width += spacing + size.width
                rows[rows.count - 1].height = max(last.height, size.height)
            } else {
                rows.append(([index], size.width, size.height))
            }
        }
        return rows
    }
}
