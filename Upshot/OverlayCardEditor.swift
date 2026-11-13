import AppKit
import SwiftUI

struct OverlayCardEditor: View {
    @State private var store = OverlayCardLayoutStore.shared

    @State private var dragging: OverlayCardAction?
    @State private var dragLocation: CGPoint = .zero
    @State private var originZone: OverlayCardZone?
    @State private var hoveredZone: OverlayCardZone?

    @State private var zoneFrames: [ZoneFrame] = []
    @State private var centerItemFrames: [CenterItemFrame] = []

    private let cardSize = CGSize(width: 210, height: 158)
    private static let cardRadius = CaptureShelfMetrics.cardRadius * 210 / CaptureShelfMetrics.cardSize.width
    private static let trayRadius = Radius.nested(inner: Radius.control, padding: Space.xs)
    private let spaceName = "cardEditor"
    private var layout: OverlayCardLayout { store.layout }

    var body: some View {
        VStack(spacing: Space.xl) {
            card

            tray

            footer
        }
        .coordinateSpace(.named(spaceName))
        .onPreferenceChange(ZoneFramesKey.self) { zoneFrames = $0 }
        .onPreferenceChange(CenterItemFramesKey.self) { centerItemFrames = $0 }
        .overlay(alignment: .topLeading) {
            if let dragging {
                FloatingMorphChip(
                    action: dragging,
                    isCorner: chipStyle(for: hoveredZone ?? originZone).isCorner
                )
                .position(dragLocation)
                .allowsHitTesting(false)
                .transition(.identity)
                .zIndex(100)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        InterfaceActionButton("Reset to Default", systemImage: "arrow.uturn.backward") {
            withAnimation(.morphIfAllowed) {
                store.reset()
            }
        }
    }


    private var card: some View {
        ZStack {
            cardBackground

            ForEach(OverlayCardCorner.allCases) { corner in
                cornerCell(corner)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner.alignment)
                    .padding(11)
            }

            centerColumn
        }
        .frame(width: cardSize.width, height: cardSize.height)
        .motion(.morph, value: layout)
        .animation(.easeOut(duration: 0.18), value: hoveredZone)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.32), Color(white: 0.17)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cardRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 10)
    }

    private func cornerCell(_ corner: OverlayCardCorner) -> some View {
        let action = layout.action(at: corner)
        let highlighted = hoveredZone == .corner(corner)

        let isFilled = action != nil && action != dragging

        return ZStack {
            if !isFilled {
                slotPlaceholder(isCircle: true, highlighted: highlighted)
            }

            if let action {
                chip(action, style: .corner)
                    .opacity(action == dragging ? 0 : 1)
            }
        }
        .frame(width: 34, height: 34)
        .background(frameReporter(.corner(corner)))
    }

    private var centerColumn: some View {
        let highlighted = hoveredZone == .center
        let visibleCount = layout.center.filter { $0 != dragging }.count

        return VStack(spacing: 7) {
            ForEach(layout.center) { action in
                ZStack {
                    chip(action, style: .pill)
                        .opacity(action == dragging ? 0 : 1)

                    if action == dragging && visibleCount == 0 {
                        slotPlaceholder(isCircle: false, highlighted: highlighted)
                            .frame(width: 104, height: 30)
                    }
                }
                .background(centerItemReporter(action))
            }

            if layout.center.isEmpty {
                slotPlaceholder(isCircle: false, highlighted: highlighted)
                    .frame(width: 104, height: 30)
            }
        }
        .padding(8)
        .frame(minWidth: 120, minHeight: 44)
        .background(frameReporter(.center))
    }


    private var tray: some View {
        let highlighted = hoveredZone == .tray
        let visibleCount = layout.hidden.filter { $0 != dragging }.count

        return VStack(alignment: .leading, spacing: Space.m) {
            Text("Hidden")
                .font(.dsCaption)
                .foregroundStyle(Palette.secondaryLabel)

            FlowLayout(spacing: Space.m) {
                if layout.hidden.isEmpty || visibleCount == 0 {
                    Text("Drop actions here to hide them")
                        .font(.dsCaption)
                        .foregroundStyle(Palette.tertiaryLabel)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                ForEach(layout.hidden) { action in
                    chip(action, style: .tray)
                        .opacity(action == dragging ? 0 : 1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Space.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Self.trayRadius, style: .continuous)
                .fill(highlighted ? Palette.selectedFill : Palette.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.trayRadius, style: .continuous)
                .strokeBorder(highlighted ? Palette.highlight : .clear, lineWidth: 2)
        )
        .motion(.morphQuick, value: hoveredZone)
        .motion(.morph, value: layout)
        .background(frameReporter(.tray))
    }


    private func chip(_ action: OverlayCardAction, style: ChipStyle) -> some View {
        ActionChip(action: action, style: style)
            .contentShape(.capsule)
            .gesture(dragGesture(for: action))
            .help(action.editorHelp)
            .transition(.asymmetric(
                insertion: .scale(scale: 0.5).combined(with: .opacity),
                removal: .opacity
            ))
    }

    private func chipStyle(for zone: OverlayCardZone?) -> ChipStyle {
        switch zone {
        case .corner: .corner
        case .tray: .tray
        default: .pill
        }
    }


    private func dragGesture(for action: OverlayCardAction) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(spaceName))
            .onChanged { value in
                if dragging == nil {
                    dragging = action
                    originZone = layout.zone(of: action)
                    dragLocation = value.location
                    hoveredZone = originZone
                }
                dragLocation = value.location

                let resolved = resolveDrop(at: value.location) ?? originZone
                if resolved != hoveredZone {
                    withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.26)) {
                        hoveredZone = resolved
                    }
                }
            }
            .onEnded { value in
                let target = resolveDrop(at: value.location) ?? originZone
                var index: Int?
                if target == .center {
                    index = centerInsertionIndex(at: value.location)
                }

                withAnimation(.morphIfAllowed) {
                    if let target {
                        var updated = layout
                        updated.place(action, into: target, centerIndex: index)
                        store.layout = updated.normalized()
                    }
                    dragging = nil
                    hoveredZone = nil
                    originZone = nil
                }
            }
    }

    private func resolveDrop(at point: CGPoint) -> OverlayCardZone? {
        for frame in zoneFrames {
            if case .corner = frame.zone, frame.rect.insetBy(dx: -16, dy: -16).contains(point) {
                return frame.zone
            }
        }
        if let center = zoneFrames.first(where: { $0.zone == .center }),
           center.rect.insetBy(dx: -14, dy: -14).contains(point),
           canDropInCenter() {
            return .center
        }
        if let tray = zoneFrames.first(where: { $0.zone == .tray }), tray.rect.contains(point) {
            return .tray
        }
        return nil
    }

    private func canDropInCenter() -> Bool {
        guard let dragging else { return false }
        if layout.center.contains(dragging) { return true }
        return layout.center.filter { $0 != dragging }.count < OverlayCardLayout.centerCapacity
    }

    private func centerInsertionIndex(at point: CGPoint) -> Int {
        let sorted = centerItemFrames
            .filter { $0.action != dragging }
            .sorted { $0.rect.midY < $1.rect.midY }

        var index = 0
        for item in sorted {
            if point.y > item.rect.midY { index += 1 } else { break }
        }
        return index
    }


    @ViewBuilder
    private func slotPlaceholder(isCircle: Bool, highlighted: Bool) -> some View {
        let stroke = highlighted ? Palette.highlight : Color.white.opacity(0.28)
        let style = StrokeStyle(lineWidth: highlighted ? 2 : 1.5, dash: highlighted ? [] : [4, 4])
        let fill = highlighted ? Palette.highlight.opacity(0.18) : Color.clear

        Group {
            if isCircle {
                Circle()
                    .strokeBorder(stroke, style: style)
                    .background(Circle().fill(fill))
            } else {
                Capsule()
                    .strokeBorder(stroke, style: style)
                    .background(Capsule().fill(fill))
            }
        }
        .scaleEffect(highlighted ? 1.12 : 1)
    }

    private func frameReporter(_ zone: OverlayCardZone) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: ZoneFramesKey.self,
                value: [ZoneFrame(zone: zone, rect: geo.frame(in: .named(spaceName)))]
            )
        }
    }

    private func centerItemReporter(_ action: OverlayCardAction) -> some View {
        GeometryReader { geo in
            Color.clear.preference(
                key: CenterItemFramesKey.self,
                value: [CenterItemFrame(action: action, rect: geo.frame(in: .named(spaceName)))]
            )
        }
    }
}


private struct FloatingMorphChip: View {
    let action: OverlayCardAction
    let isCorner: Bool

    private static let diameter: CGFloat = 32
    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    private var pillWidth: CGFloat {
        let textWidth = (action.label() as NSString)
            .size(withAttributes: [.font: Self.labelFont]).width
        return max(Self.diameter, ceil(textWidth) + 24)
    }

    var body: some View {
        let capsuleWidth = isCorner ? Self.diameter : pillWidth

        Capsule()
            .fill(.white)
            .frame(width: capsuleWidth, height: Self.diameter)
            .overlay {
                ZStack {
                    Image(systemName: action.symbol())
                        .font(.system(size: 13, weight: .bold))
                        .opacity(isCorner ? 1 : 0)
                        .scaleEffect(isCorner ? 1 : 0.4, anchor: .center)

                    Text(action.label())
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                        .opacity(isCorner ? 0 : 1)
                        .scaleEffect(isCorner ? 0.4 : 1, anchor: .center)
                }
                .foregroundStyle(.black)
            }
            .clipShape(.capsule)
            .overlay(
                Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
            )
            .frame(width: pillWidth, height: Self.diameter)
            .shadow(color: .black.opacity(0.32), radius: 12, x: 0, y: 7)
            .scaleEffect(1.08, anchor: .center)
    }
}


enum ChipStyle: Equatable {
    case corner
    case pill
    case tray

    var isCorner: Bool { self == .corner }
}

private struct ActionChip: View {
    let action: OverlayCardAction
    let style: ChipStyle
    var lifted: Bool = false

    private static let cornerDiameter: CGFloat = 32
    private static let labelFont = NSFont.systemFont(ofSize: 12, weight: .semibold)

    private var pillWidth: CGFloat {
        let textWidth = (action.label() as NSString)
            .size(withAttributes: [.font: Self.labelFont]).width
        return max(Self.cornerDiameter, ceil(textWidth) + 24)
    }

    var body: some View {
        let isCorner = style.isCorner

        ZStack {
            Image(systemName: action.symbol())
                .font(.system(size: 13, weight: .bold))
                .opacity(isCorner ? 1 : 0)
                .scaleEffect(isCorner ? 1 : 0.4, anchor: .center)
                .blur(radius: isCorner ? 0 : 2)

            Text(action.label())
                .font(.system(size: 12, weight: .semibold))
                .fixedSize()
                .opacity(isCorner ? 0 : 1)
                .scaleEffect(isCorner ? 0.4 : 1, anchor: .center)
                .blur(radius: isCorner ? 2 : 0)
        }
        .foregroundStyle(.black)
        .frame(width: isCorner ? Self.cornerDiameter : pillWidth, height: Self.cornerDiameter, alignment: .center)
        .background(.white, in: .capsule)
        .clipShape(.capsule)
        .overlay(
            Capsule().strokeBorder(.black.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(lifted ? 0.32 : 0.16), radius: lifted ? 12 : 4, x: 0, y: lifted ? 7 : 2)
        .scaleEffect(lifted ? 1.08 : 1, anchor: .center)
    }
}


private struct ZoneFrame: Equatable {
    let zone: OverlayCardZone
    let rect: CGRect
}

private struct ZoneFramesKey: PreferenceKey {
    static let defaultValue: [ZoneFrame] = []
    static func reduce(value: inout [ZoneFrame], nextValue: () -> [ZoneFrame]) {
        value.append(contentsOf: nextValue())
    }
}

private struct CenterItemFrame: Equatable {
    let action: OverlayCardAction
    let rect: CGRect
}

private struct CenterItemFramesKey: PreferenceKey {
    static let defaultValue: [CenterItemFrame] = []
    static func reduce(value: inout [CenterItemFrame], nextValue: () -> [CenterItemFrame]) {
        value.append(contentsOf: nextValue())
    }
}


private extension OverlayCardCorner {
    var alignment: Alignment {
        switch self {
        case .topLeading: .topLeading
        case .topTrailing: .topTrailing
        case .bottomLeading: .bottomLeading
        case .bottomTrailing: .bottomTrailing
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                totalHeight += rowHeight + spacing
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        maxRowWidth = max(maxRowWidth, x - spacing)

        let width = maxWidth == .infinity ? maxRowWidth : maxWidth
        return CGSize(width: max(0, width), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private extension OverlayCardAction {
    var editorHelp: String {
        guard let shortcutKey else { return detail }
        return "\(detail). Shortcut: \(shortcutKey)"
    }

    var shortcutKey: String? {
        switch self {
        case .copy: "C"
        case .save: "S"
        case .annotate: "E"
        case .pin: "P"
        case .view: "Space"
        case .close: "Delete"
        case .compress, .upload, .delete: nil
        }
    }
}
