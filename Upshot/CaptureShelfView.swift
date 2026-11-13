import SwiftUI

struct CaptureShelfView: View {
    @State private var shelf = CaptureShelf.shared
    @State private var isShelfHovered = UpshotStorage.isRenderingStates && StateRenderer.scenario.contains("hover")
    @State private var hoverEndTask: Task<Void, Never>?
    @State private var hasEntered = UpshotStorage.isRenderingStates
    @AppStorage(UpshotPreferences.previewPositionKey) private var positionRaw = PreviewOverlayPosition.right.rawValue
    @AppStorage(UpshotPreferences.shelfHandlePositionKey) private var handlePosition = 0.5
    @AppStorage(UpshotPreferences.previewOverlaySizeKey) private var overlaySize = QuickAccessOverlaySize.small

    private var isLeft: Bool { positionRaw == PreviewOverlayPosition.left.rawValue }
    private var outward: CGFloat { isLeft ? -1 : 1 }
    private var edge: HorizontalAlignment { isLeft ? .leading : .trailing }
    private var cardTransition: AnyTransition {
        .offset(x: CaptureShelfMetrics.panelWidth * outward).combined(with: .opacity)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: Alignment(horizontal: edge, vertical: .bottom)) {
                column
                    .padding(isLeft ? .leading : .trailing, CaptureShelfMetrics.edgeInset)
                    .padding(.bottom, CaptureShelfMetrics.bottomInset)
                    .offset(x: shelf.isTucked || !hasEntered ? CaptureShelfMetrics.panelWidth * outward : 0)

                if shelf.isTucked, !shelf.items.isEmpty {
                    CaptureShelfHandle(
                        count: shelf.items.count,
                        isLeft: isLeft,
                        trackHeight: proxy.size.height,
                        position: $handlePosition
                    ) {
                        shelf.open()
                    }
                    .transition(.offset(x: 60 * outward))
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: Alignment(horizontal: edge, vertical: .bottom))
            .onAppear { updateCapacity(forHeight: proxy.size.height) }
            .task {
                guard !UpshotStorage.isRenderingStates else { return }
                await Task.yield()
                shelf.noteMotion()
                withAnimation(CaptureShelf.slideIfAllowed) { hasEntered = true }
            }
            .onChange(of: proxy.size.height) { _, height in
                updateCapacity(forHeight: height)
            }
            .onChange(of: overlaySize) { _, size in
                CaptureShelfPresenter.shared.applyPlacement()
                updateCapacity(forHeight: proxy.size.height)
                AppLog.event("quick_access", "quick_access_overlay", fields: ["capacity": String(describing: shelf.capacity), "height": String(describing: CaptureShelfMetrics.cardSize.height), "size": String(describing: size.rawValue), "width": String(describing: CaptureShelfMetrics.cardSize.width)])
            }
        }
        .onChange(of: positionRaw) { _, _ in
            CaptureShelfPresenter.shared.applyPlacement()
        }
    }

    private var column: some View {
        VStack(alignment: edge, spacing: CaptureShelfMetrics.cardSpacing) {
            if showsHeader {
                CaptureShelfHeader(
                    count: shelf.items.count,
                    hasRecordings: shelf.items.contains { $0.kind == .video },
                    isLeft: isLeft,
                    onTuck: { shelf.tuck(.user) },
                    onClearAll: { shelf.dismissAll() }
                )
                .transition(.rise)
            }

            ForEach(shelf.items) { item in
                CaptureShelfCard(item: item, shelf: shelf)
                    .transition(cardTransition)
            }
        }
        .frame(width: CaptureShelfMetrics.cardSize.width)
        .onHover(perform: setShelfHovered)
        .motion(.morphQuick, value: showsHeader)
    }

    private func updateCapacity(forHeight height: CGFloat) {
        guard height > 0 else { return }
        shelf.capacity = CaptureShelfMetrics.capacity(forHeight: height)
    }

    private var showsHeader: Bool {
        isShelfHovered && !shelf.isTucked && !shelf.isMoving && !shelf.items.isEmpty && shelf.draggingID == nil
    }

    private func setShelfHovered(_ isHovered: Bool) {
        hoverEndTask?.cancel()
        if isHovered {
            isShelfHovered = true
        } else {
            hoverEndTask = Task {
                try? await Task.sleep(for: .milliseconds(220))
                guard !Task.isCancelled else { return }
                isShelfHovered = false
            }
        }
    }
}

private struct CaptureShelfHeader: View {
    let count: Int
    let hasRecordings: Bool
    let isLeft: Bool
    let onTuck: () -> Void
    let onClearAll: () -> Void

    private static var segmentHeight: CGFloat {
        InterfaceMetrics.modeSwitchHeight - Space.xxs * 2
    }

    var body: some View {
        HStack(spacing: Space.s) {
            if isLeft { tuckButton }

            InterfacePanel(.pill, padding: Space.xxs) {
                Button(action: onClearAll) {
                    Text("Clear All")
                        .font(.dsSegment)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                        .padding(.horizontal, Space.ml)
                        .frame(height: Self.segmentHeight)
                }
                .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.pill))
                .help("Dismiss \(title.lowercased())")
            }

            if !isLeft { tuckButton }
        }
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var tuckButton: some View {
        InterfacePanel(.pill, padding: Space.xxs) {
            Button(action: onTuck) {
                Image(systemName: isLeft ? "chevron.left" : "chevron.right")
                    .font(.system(size: IconSize.segment, weight: .semibold))
                    .foregroundStyle(Palette.label)
                    .frame(width: Self.segmentHeight, height: Self.segmentHeight)
            }
            .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.pill))
            .help("Tuck into the edge")
            .accessibilityLabel("Tuck into the edge")
        }
    }

    private var title: String {
        let noun = hasRecordings ? "Capture" : "Screenshot"
        return count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }
}

private struct CaptureShelfHandle: View {
    let count: Int
    let isLeft: Bool
    let trackHeight: CGFloat
    @Binding var position: Double
    let action: () -> Void

    @State private var isHovered = false
    @State private var dragStartTop: CGFloat?
    @State private var dragTop: CGFloat?

    private static var height: CGFloat { InterfaceMetrics.toolbarButtonHeight }
    private static var width: CGFloat { InterfaceMetrics.modeSwitchHeight }
    private static var margin: CGFloat { Space.xxxl }
    private static var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.panel, style: .continuous) }

    private var travel: CGFloat {
        max(0, trackHeight - Self.height - Self.margin * 2)
    }

    private var restingTop: CGFloat {
        Self.margin + travel * CGFloat(min(max(position, 0), 1))
    }

    var body: some View {
        tab
            .frame(maxHeight: .infinity, alignment: .top)
            .offset(y: dragTop ?? restingTop)
    }

    private var isEngaged: Bool { isHovered || dragTop != nil }

    private var tab: some View {
        VStack(spacing: Space.xs) {
            Image(systemName: isLeft ? "chevron.right" : "chevron.left")
                .font(.system(size: IconSize.segment, weight: .semibold))
            Text("\(count)")
                .font(.dsNumeric)
                .contentTransition(.numericText())
        }
        .foregroundStyle(Palette.label)
        .frame(width: Self.width, height: Self.height)
        .padding(isLeft ? .leading : .trailing, Radius.panel)
        .background(isEngaged ? Palette.floatingHoverFill : .clear, in: Self.shape)
        .interfacePanelSurface(cornerRadius: Radius.panel)
        .contentShape(Self.shape)
        .gesture(pressAndDrag)
        .pointerStyle(dragTop == nil ? .grabIdle : .grabActive)
        .onHover { isHovered = $0 }
        .offset(x: isLeft ? -Radius.panel : Radius.panel)
        .motion(.morphQuick, value: isEngaged)
        .motion(.morphQuick, value: count)
        .help(count == 1 ? "Show 1 capture · drag to move" : "Show \(count) captures · drag to move")
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("Show captures")
        .accessibilityValue("\(count)")
        .accessibilityAction { action() }
    }

    private static let clickSlop: CGFloat = 6

    private var pressAndDrag: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStartTop ?? restingTop
                dragStartTop = start
                guard dragTop != nil || value.translation.isBeyond(Self.clickSlop) else { return }
                dragTop = min(max(start + value.translation.height, Self.margin), Self.margin + travel)
            }
            .onEnded { _ in
                if let dragTop {
                    if travel > 0 {
                        position = Double((dragTop - Self.margin) / travel)
                    }
                } else {
                    action()
                }
                dragTop = nil
                dragStartTop = nil
            }
    }
}

private extension CGSize {
    func isBeyond(_ distance: CGFloat) -> Bool {
        width * width + height * height > distance * distance
    }
}
