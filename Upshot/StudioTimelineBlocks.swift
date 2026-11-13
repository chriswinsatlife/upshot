import AppKit
import SwiftUI

enum StudioBlockMetrics {
    static let cornerRadius: CGFloat = 8
    static let inset: CGFloat = 3
    static let minimumWidth: CGFloat = 24
    static let handleWidth: CGFloat = 8
    static let rimWidth: CGFloat = 2
    static let selectionCornerRadius: CGFloat = 6
    static let selectedCornerRadius: CGFloat = selectionCornerRadius - rimWidth
    static let edgeOutset: CGFloat = 4
    static let edgeInset: CGFloat = 6
    static let handleOverlap: CGFloat = 2
    static let labelInset: CGFloat = 9
    static let dragThreshold: CGFloat = 3

    static var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }
}

extension EnvironmentValues {
    @Entry var studioBlockCornerRadius: CGFloat = StudioBlockMetrics.cornerRadius
}

private struct StudioBlockClip: ViewModifier {
    @Environment(\.studioBlockCornerRadius) private var cornerRadius

    func body(content: Content) -> some View {
        content.clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension View {
    func studioBlockClip() -> some View {
        modifier(StudioBlockClip())
    }
}

struct StudioLaneBlock<Item: Identifiable>: Identifiable where Item.ID == UUID {
    let item: Item
    let editorStart: TimeInterval
    let editorEnd: TimeInterval

    var id: UUID { item.id }
    var editorLength: TimeInterval { max(0, editorEnd - editorStart) }
}

enum StudioBlockEditKind: Equatable {
    case move
    case trimLeading
    case trimTrailing
}

struct StudioBlockEdit<Item: Identifiable> where Item.ID == UUID {
    let base: StudioLaneBlock<Item>
    let kind: StudioBlockEditKind
    let delta: TimeInterval
}

enum StudioLaneEmptyBehavior {
    case scrub
    case create(
        tint: Color,
        minimumLength: TimeInterval,
        commit: (ClosedRange<TimeInterval>) -> Void
    )
}

struct StudioLaneSpan: Equatable {
    let id: UUID
    let editorStart: TimeInterval
    let editorEnd: TimeInterval
}

enum StudioLaneOverlap {
    case allowed
    case forbidden(spans: [StudioLaneSpan])
}

func studioDraftRange(
    anchor: TimeInterval,
    pointer: TimeInterval,
    gap: ClosedRange<TimeInterval>,
    minimumLength: TimeInterval
) -> ClosedRange<TimeInterval>? {
    guard gap.contains(anchor), gap.upperBound - gap.lowerBound >= minimumLength else { return nil }
    let pointer = min(max(pointer, gap.lowerBound), gap.upperBound)
    var lower = min(anchor, pointer)
    var upper = max(anchor, pointer)
    if upper - lower < minimumLength {
        if pointer >= anchor {
            upper = min(lower + minimumLength, gap.upperBound)
            lower = upper - minimumLength
        } else {
            lower = max(upper - minimumLength, gap.lowerBound)
            upper = lower + minimumLength
        }
    }
    return lower...upper
}

func studioGap(
    around time: TimeInterval,
    spans: [StudioLaneSpan],
    duration: TimeInterval
) -> ClosedRange<TimeInterval>? {
    guard !spans.contains(where: { $0.editorStart < time && time < $0.editorEnd }) else { return nil }
    let floor = spans.map(\.editorEnd).filter { $0 <= time }.max() ?? 0
    let ceiling = spans.map(\.editorStart).filter { $0 >= time }.min() ?? duration
    return floor...max(floor, ceiling)
}

struct StudioBlockLaneActions<Item: Identifiable> where Item.ID == UUID {
    let select: (Item) -> Void
    let begin: (StudioBlockEditKind) -> Void
    let edit: (StudioBlockEdit<Item>) -> Void
    let end: (StudioBlockEditKind) -> Void
}

struct StudioBlockState {
    let width: CGFloat
    let height: CGFloat
    let isSelected: Bool
    let isHovered: Bool
}

struct StudioBlockFrame: Equatable {
    let minX: CGFloat
    let width: CGFloat

    var maxX: CGFloat { minX + width }

    init(editorStart: TimeInterval, editorEnd: TimeInterval, scale: StudioTimelineScale) {
        let startX = scale.x(for: editorStart)
        let natural = CGFloat(max(0, editorEnd - editorStart)) * scale.pointsPerSecond
        let visible = min(natural, scale.contentWidth - startX)
        let width = min(max(StudioBlockMetrics.minimumWidth, visible), scale.contentWidth)
        self.width = width
        self.minX = min(startX, max(0, scale.contentWidth - width))
    }

    var edgeInset: CGFloat {
        min(StudioBlockMetrics.edgeInset, width * 0.2)
    }
}

enum StudioBlockEdge: Equatable {
    case leading
    case trailing
}

enum StudioBlockTarget: Equatable {
    case empty
    case body(UUID)
    case edge(UUID, StudioBlockEdge)

    var blockID: UUID? {
        switch self {
        case .empty: nil
        case .body(let id), .edge(let id, _): id
        }
    }
}

struct StudioBlockHitTester {
    struct Entry {
        let id: UUID
        let frame: StudioBlockFrame
    }

    let entries: [Entry]
    let selectedID: UUID?

    func target(atX x: CGFloat) -> StudioBlockTarget {
        if let selected = entries.last(where: { $0.id == selectedID }) {
            let frame = selected.frame
            let reach = StudioBlockMetrics.handleWidth
            let overlap = StudioBlockMetrics.handleOverlap
            if x >= frame.minX - reach, x < frame.minX + overlap {
                return .edge(selected.id, .leading)
            }
            if x > frame.maxX - overlap, x <= frame.maxX + reach {
                return .edge(selected.id, .trailing)
            }
            if x >= frame.minX, x <= frame.maxX {
                return .body(selected.id)
            }
        }

        for entry in entries.reversed() where entry.id != selectedID {
            let frame = entry.frame
            if x >= frame.minX + frame.edgeInset, x <= frame.maxX - frame.edgeInset {
                return .body(entry.id)
            }
        }

        var nearest: (target: StudioBlockTarget, isInside: Bool, distance: CGFloat)?
        for entry in entries where entry.id != selectedID {
            let frame = entry.frame
            let isInside = x >= frame.minX && x <= frame.maxX
            let candidates: [(StudioBlockEdge, CGFloat, ClosedRange<CGFloat>)] = [
                (.leading, frame.minX, (frame.minX - StudioBlockMetrics.edgeOutset)...(frame.minX + frame.edgeInset)),
                (.trailing, frame.maxX, (frame.maxX - frame.edgeInset)...(frame.maxX + StudioBlockMetrics.edgeOutset)),
            ]
            for (edge, edgeX, reach) in candidates where reach.contains(x) {
                let distance = abs(x - edgeX)
                let isBetter = nearest.map { best in
                    isInside != best.isInside ? isInside : distance < best.distance
                } ?? true
                if isBetter {
                    nearest = (.edge(entry.id, edge), isInside, distance)
                }
            }
        }
        return nearest?.target ?? .empty
    }
}

struct StudioBlockLane<Item: Identifiable, Content: View, Menu: View, Decoration: View>: View
where Item.ID == UUID {
    let model: RecordingStudioModel
    let blocks: [StudioLaneBlock<Item>]
    let selectedID: UUID?
    let scale: StudioTimelineScale
    let height: CGFloat
    let overlap: StudioLaneOverlap
    let empty: StudioLaneEmptyBehavior
    var onScrubbing: ((Bool) -> Void)?
    let actions: StudioBlockLaneActions<Item>
    @ViewBuilder let decoration: () -> Decoration
    @ViewBuilder let content: (StudioLaneBlock<Item>, StudioBlockState) -> Content
    @ViewBuilder let menu: (StudioLaneBlock<Item>) -> Menu
    let help: (StudioLaneBlock<Item>) -> String

    private enum Press {
        case block(StudioLaneBlock<Item>, StudioBlockEditKind)
        case editing(StudioLaneBlock<Item>, StudioBlockEditKind)
        case empty(startTime: TimeInterval)
        case creating(startTime: TimeInterval)
        case scrubbing
    }

    @State private var press: Press?
    @State private var draft: ClosedRange<TimeInterval>?
    @State private var hover: StudioBlockTarget = .empty

    private var blockHeight: CGFloat {
        height - StudioBlockMetrics.inset * 2
    }

    var body: some View {
        let frames = Dictionary(uniqueKeysWithValues: blocks.map {
            ($0.id, StudioBlockFrame(editorStart: $0.editorStart, editorEnd: $0.editorEnd, scale: scale))
        })
        let selected = blocks.first { $0.id == selectedID }

        ZStack(alignment: .topLeading) {
            Color.clear

            decoration()
                .allowsHitTesting(false)

            if let draft, case .create(let tint, _, _) = empty {
                StudioDraftBlock(
                    frame: StudioBlockFrame(editorStart: draft.lowerBound, editorEnd: draft.upperBound, scale: scale),
                    height: blockHeight,
                    tint: tint
                )
            }

            ForEach(blocks.filter { $0.id != selectedID } + (selected.map { [$0] } ?? [])) { block in
                if let frame = frames[block.id] {
                    blockView(block, frame: frame)
                }
            }

            if let selected, let frame = frames[selected.id] {
                StudioSelectionFrame(blockWidth: frame.width, blockHeight: blockHeight)
                    .offset(
                        x: frame.minX - StudioBlockMetrics.handleWidth,
                        y: StudioBlockMetrics.inset - StudioBlockMetrics.rimWidth
                    )
                    .allowsHitTesting(false)
            }
        }
        .frame(height: height, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(dragGesture(frames: frames))
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                let target = hitTester(frames).target(atX: location.x)
                if target != hover { hover = target }
            case .ended:
                if hover != .empty { hover = .empty }
            }
        }
        .pointerStyle(pointerStyle)
    }

    @ViewBuilder
    private func blockView(_ block: StudioLaneBlock<Item>, frame: StudioBlockFrame) -> some View {
        let isSelected = block.id == selectedID
        let state = StudioBlockState(
            width: frame.width,
            height: blockHeight,
            isSelected: isSelected,
            isHovered: activeTarget.blockID == block.id
        )
        let cornerRadius = isSelected ? StudioBlockMetrics.selectedCornerRadius : StudioBlockMetrics.cornerRadius
        content(block, state)
            .environment(\.studioBlockCornerRadius, cornerRadius)
            .frame(width: frame.width, height: blockHeight, alignment: .leading)
            .overlay {
                if !isSelected, case .edge(block.id, let edge) = activeTarget {
                    StudioBlockGrip()
                        .frame(maxWidth: .infinity, alignment: edge == .leading ? .leading : .trailing)
                        .padding(.horizontal, 3)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .contextMenu { menu(block) }
            .help(help(block))
            .offset(x: frame.minX, y: StudioBlockMetrics.inset)
    }

    private func hitTester(_ frames: [UUID: StudioBlockFrame]) -> StudioBlockHitTester {
        StudioBlockHitTester(
            entries: blocks.compactMap { block in
                frames[block.id].map { .init(id: block.id, frame: $0) }
            },
            selectedID: selectedID
        )
    }

    private var activeTarget: StudioBlockTarget {
        switch press {
        case .block(let block, let kind), .editing(let block, let kind):
            switch kind {
            case .move: .body(block.id)
            case .trimLeading: .edge(block.id, .leading)
            case .trimTrailing: .edge(block.id, .trailing)
            }
        case .empty, .creating, .scrubbing:
            .empty
        case nil:
            hover
        }
    }

    private var pointerStyle: PointerStyle? {
        guard case .edge(_, let edge) = activeTarget else { return nil }
        return .frameResize(position: edge == .leading ? .leading : .trailing)
    }

    private func dragGesture(frames: [UUID: StudioBlockFrame]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard scale.pointsPerSecond > 0 else { return }
                if press == nil {
                    begin(at: value.startLocation.x, frames: frames)
                }
                update(translation: value.location.x - value.startLocation.x, x: value.location.x)
            }
            .onEnded { _ in finish() }
    }

    private func begin(at x: CGFloat, frames: [UUID: StudioBlockFrame]) {
        model.pause()
        let target = hitTester(frames).target(atX: x)
        if let id = target.blockID, let block = blocks.first(where: { $0.id == id }) {
            actions.select(block.item)
            let kind: StudioBlockEditKind = switch target {
            case .edge(_, .leading): .trimLeading
            case .edge(_, .trailing): .trimTrailing
            default: .move
            }
            press = .block(block, kind)
            return
        }

        model.clearTimelineSelection()
        let time = scale.time(forX: x)
        model.seek(to: time)
        onScrubbing?(true)
        switch empty {
        case .scrub: press = .scrubbing
        case .create: press = .empty(startTime: time)
        }
    }

    private func update(translation: CGFloat, x: CGFloat) {
        let time = scale.time(forX: x)
        switch press {
        case .block(let block, let kind):
            let threshold = kind == .move ? StudioBlockMetrics.dragThreshold : 0.5
            guard abs(translation) >= threshold else { return }
            actions.begin(kind)
            press = .editing(block, kind)
            edit(block, kind: kind, translation: translation)
        case .editing(let block, let kind):
            edit(block, kind: kind, translation: translation)
        case .empty(let startTime):
            if abs(translation) < StudioBlockMetrics.dragThreshold {
                model.seek(to: time)
                return
            }
            onScrubbing?(false)
            press = .creating(startTime: startTime)
            draft = draftRange(from: startTime, to: time)
        case .creating(let startTime):
            draft = draftRange(from: startTime, to: time)
        case .scrubbing:
            model.seek(to: time)
        case nil:
            break
        }
    }

    private func edit(_ block: StudioLaneBlock<Item>, kind: StudioBlockEditKind, translation: CGFloat) {
        var delta = Double(translation) * scale.secondsPerPoint
        if case .forbidden(let spans) = overlap {
            let room = room(around: block, among: spans)
            switch kind {
            case .move:
                delta = min(max(delta, room.lowerBound - block.editorStart),
                            room.upperBound - block.editorEnd)
            case .trimLeading:
                delta = max(delta, room.lowerBound - block.editorStart)
            case .trimTrailing:
                delta = min(delta, room.upperBound - block.editorEnd)
            }
        }
        actions.edit(StudioBlockEdit(base: block, kind: kind, delta: delta))
    }

    private func room(around block: StudioLaneBlock<Item>, among spans: [StudioLaneSpan]) -> ClosedRange<TimeInterval> {
        let others = spans.filter { $0.id != block.id }
        let floor = others.map(\.editorEnd).filter { $0 <= block.editorStart + 0.0001 }.max() ?? 0
        let ceiling = others.map(\.editorStart).filter { $0 >= block.editorEnd - 0.0001 }.min() ?? scale.duration
        return floor...max(floor, ceiling)
    }

    private func finish() {
        switch press {
        case .editing(_, let kind):
            actions.end(kind)
        case .creating:
            if let draft, case .create(_, _, let commit) = empty {
                commit(draft)
            }
        case .empty, .scrubbing:
            onScrubbing?(false)
        case .block, nil:
            break
        }
        press = nil
        draft = nil
    }

    private func draftRange(from start: TimeInterval, to current: TimeInterval) -> ClosedRange<TimeInterval>? {
        guard case .create(_, let minimumLength, _) = empty else { return nil }
        let gap: ClosedRange<TimeInterval>? = switch overlap {
        case .allowed: 0...scale.duration
        case .forbidden(let spans): studioGap(around: start, spans: spans, duration: scale.duration)
        }
        guard let gap else { return nil }
        return studioDraftRange(anchor: start, pointer: current, gap: gap, minimumLength: minimumLength)
    }
}

extension StudioBlockLane where Decoration == EmptyView {
    init(
        model: RecordingStudioModel,
        blocks: [StudioLaneBlock<Item>],
        selectedID: UUID?,
        scale: StudioTimelineScale,
        height: CGFloat,
        overlap: StudioLaneOverlap = .allowed,
        empty: StudioLaneEmptyBehavior,
        onScrubbing: ((Bool) -> Void)? = nil,
        actions: StudioBlockLaneActions<Item>,
        @ViewBuilder content: @escaping (StudioLaneBlock<Item>, StudioBlockState) -> Content,
        @ViewBuilder menu: @escaping (StudioLaneBlock<Item>) -> Menu,
        help: @escaping (StudioLaneBlock<Item>) -> String
    ) {
        self.init(
            model: model,
            blocks: blocks,
            selectedID: selectedID,
            scale: scale,
            height: height,
            overlap: overlap,
            empty: empty,
            onScrubbing: onScrubbing,
            actions: actions,
            decoration: { EmptyView() },
            content: content,
            menu: menu,
            help: help
        )
    }
}

func studioMovedSourceRange(
    model: RecordingStudioModel,
    editorStart: TimeInterval,
    editorLength: TimeInterval
) -> (start: TimeInterval, end: TimeInterval) {
    let start = min(max(0, editorStart), max(0, model.duration - editorLength))
    return (
        model.sourceTime(atEditorTime: start),
        model.sourceTime(atEditorTime: start + editorLength)
    )
}

struct StudioBlockStyle {
    let tint: NSColor
    var onTint: Color = .white

    static let zoom = StudioBlockStyle(tint: .controlAccentColor)
    static let layout = StudioBlockStyle(tint: .systemGreen)
    static let text = StudioBlockStyle(tint: .systemPurple)
    static let image = StudioBlockStyle(tint: .systemTeal)
    static let effect = StudioBlockStyle(tint: .systemGray)
    static let audio = StudioBlockStyle(tint: .systemIndigo)

    func fill(isHovering: Bool) -> Color {
        let tint = tint
        return Color(nsColor: NSColor(name: nil) { appearance in
            var resolved = tint
            appearance.performAsCurrentDrawingAppearance {
                resolved = tint.usingColorSpace(.sRGB) ?? tint
            }
            let lift = (appearance.isDarkAppearance ? 0 : 0.08) + (isHovering ? 0.1 : 0)
            return lift > 0 ? resolved.blended(withFraction: lift, of: .white) ?? resolved : resolved
        })
    }
}

struct StudioBlockSurface<Fill: ShapeStyle>: View {
    let fill: Fill
    @Environment(\.studioBlockCornerRadius) private var cornerRadius

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape.fill(fill)
            .overlay {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(0.14), .white.opacity(0)],
                    startPoint: .top,
                    endPoint: .center
                ))
            }
            .overlay {
                shape.strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5)
            }
    }
}

struct StudioBlockHatch: View {
    let color: Color
    var spacing: CGFloat = 6
    var lineWidth: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += spacing
            }
            context.stroke(path, with: .color(color), lineWidth: lineWidth)
        }
        .studioBlockClip()
    }
}

struct StudioBlockLabel: View {
    let systemImage: String
    let title: String
    var detail: String?
    let state: StudioBlockState
    let color: Color
    var verticalAlignment: VerticalAlignment = .center

    var body: some View {
        line
            .frame(
                width: state.width,
                height: state.height,
                alignment: Alignment(horizontal: .leading, vertical: verticalAlignment)
            )
    }

    @ViewBuilder
    private var line: some View {
        let width = state.width
        if width >= StudioBlockMetrics.labelInset * 2 + 14 {
            HStack(spacing: 5) {
                glyph
                ViewThatFits(in: .horizontal) {
                    if let detail {
                        HStack(spacing: 6) {
                            titleText
                            Text(detail)
                                .font(.system(size: 10.5).monospacedDigit())
                                .opacity(0.8)
                        }
                        .fixedSize()
                    }
                    titleText
                        .fixedSize()
                    if width >= 88 {
                        titleText
                            .truncationMode(.tail)
                    } else {
                        Color.clear.frame(width: 0, height: 0)
                    }
                }
            }
            .lineLimit(1)
            .foregroundStyle(color)
            .padding(.horizontal, StudioBlockMetrics.labelInset)
            .frame(width: width, alignment: .leading)
            .allowsHitTesting(false)
        } else {
            glyph
                .foregroundStyle(color)
                .frame(width: width)
                .allowsHitTesting(false)
        }
    }

    private var glyph: some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .medium))
    }

    private var titleText: Text {
        Text(title)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
    }
}

struct StudioSelectionFrame: View {
    let blockWidth: CGFloat
    let blockHeight: CGFloat

    var body: some View {
        StudioSelectionFrameShape()
            .fill(Color(nsColor: .systemYellow), style: FillStyle(eoFill: true))
            .overlay(alignment: .leading) { grip }
            .overlay(alignment: .trailing) { grip }
            .frame(
                width: blockWidth + StudioBlockMetrics.handleWidth * 2,
                height: blockHeight + StudioBlockMetrics.rimWidth * 2
            )
    }

    private var grip: some View {
        Capsule()
            .fill(Color.black.opacity(0.55))
            .frame(width: 1.5, height: 10)
            .frame(width: StudioBlockMetrics.handleWidth)
    }
}

private struct StudioSelectionFrameShape: Shape {
    func path(in rect: CGRect) -> Path {
        let rim = StudioBlockMetrics.rimWidth
        var path = Path(roundedRect: rect, cornerRadius: StudioBlockMetrics.selectionCornerRadius, style: .continuous)
        let block = rect.insetBy(dx: StudioBlockMetrics.handleWidth, dy: rim)
        if block.width > 0, block.height > 0 {
            path.addPath(Path(roundedRect: block, cornerRadius: StudioBlockMetrics.selectedCornerRadius, style: .continuous))
        }
        return path
    }
}

struct StudioBlockGrip: View {
    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.9))
            .frame(width: 2, height: 10)
            .shadow(color: .black.opacity(0.25), radius: 0.5)
    }
}

private struct StudioDraftBlock: View {
    let frame: StudioBlockFrame
    let height: CGFloat
    let tint: Color

    var body: some View {
        let shape = StudioBlockMetrics.shape
        shape
            .fill(tint.opacity(0.22))
            .overlay {
                shape.strokeBorder(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
            .frame(width: frame.width, height: height)
            .offset(x: frame.minX, y: StudioBlockMetrics.inset)
            .allowsHitTesting(false)
    }
}
