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
            .onAppear { shelf.capacity = CaptureShelfMetrics.capacity(forHeight: proxy.size.height) }
            .task {
                guard !UpshotStorage.isRenderingStates else { return }
                await Task.yield()
                shelf.noteMotion()
                withAnimation(CaptureShelf.slideIfAllowed) { hasEntered = true }
            }
            .onChange(of: proxy.size.height) { _, height in
                shelf.capacity = CaptureShelfMetrics.capacity(forHeight: height)
            }
            .onChange(of: overlaySize) { _, size in
                CaptureShelfPresenter.shared.applyPlacement()
                shelf.capacity = CaptureShelfMetrics.capacity(forHeight: proxy.size.height)
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
                .padding(.bottom, CaptureShelfMetrics.headerSpacing - CaptureShelfMetrics.cardSpacing)
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

    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: GlassMetrics.containerSpacing) {
            HStack(spacing: GlassMetrics.gap) {
                if isLeft { tuckButton }

                GlassCapsuleButton(title: "Clear All", height: CaptureShelfMetrics.headerHeight, action: onClearAll)
                    .catchesClicks(in: Capsule())
                    .help("Dismiss \(title.lowercased())")
                    .glassEffectID("clear", in: glass)

                if !isLeft { tuckButton }
            }
        }
        .frame(height: CaptureShelfMetrics.headerHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private var tuckButton: some View {
        GlassIconButton(
            systemImage: isLeft ? "chevron.left" : "chevron.right",
            help: "Tuck into the edge",
            size: CaptureShelfMetrics.headerHeight,
            symbolSize: 10,
            action: onTuck
        )
        .catchesClicks(in: Circle())
        .glassEffectID("tuck", in: glass)
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

    private static let height: CGFloat = 64
    private static let margin: CGFloat = 24

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

    private var tab: some View {
        VStack(spacing: 6) {
            Image(systemName: isLeft ? "chevron.right" : "chevron.left")
                .font(.system(size: 9, weight: .bold))
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold).monospacedDigit())
                .contentTransition(.numericText())
        }
        .foregroundStyle(Palette.label)
        .frame(width: isHovered || dragTop != nil ? 30 : 24, height: Self.height)
        .contentShape(Rectangle())
        .glassEffect(.regular.interactive(), in: handleShape)
        .catchesClicks(in: handleShape)
        .gesture(pressAndDrag)
        .pointerStyle(dragTop == nil ? .grabIdle : .grabActive)
        .padding(isLeft ? .leading : .trailing, 3)
        .onHover { isHovered = $0 }
        .motion(.morphQuick, value: isHovered)
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

    private var handleShape: UnevenRoundedRectangle {
        let outer: CGFloat = 8
        let inner: CGFloat = 13
        return UnevenRoundedRectangle(
            topLeadingRadius: isLeft ? outer : inner,
            bottomLeadingRadius: isLeft ? outer : inner,
            bottomTrailingRadius: isLeft ? inner : outer,
            topTrailingRadius: isLeft ? inner : outer,
            style: .continuous
        )
    }
}

private extension View {
    func catchesClicks(in shape: some Shape) -> some View {
        background(shape.fill(Color.black.opacity(0.01)))
    }
}

private extension CGSize {
    func isBeyond(_ distance: CGFloat) -> Bool {
        width * width + height * height > distance * distance
    }
}
