import AppKit
import SwiftUI

enum BarMetrics {
    static let controlSize: CGFloat = 40
    static let height: CGFloat = 52
    static let cornerRadius: CGFloat = 16
    static let itemSpacing: CGFloat = 2
    static let horizontalPadding: CGFloat = 6

    static let shadowSlack: CGFloat = 28

    static let visibilityBannerHeight: CGFloat = 36
    static let visibilityBannerOverlap: CGFloat = 8
    static let visibilityBannerInset: CGFloat = 14
    static var bottomSlack: CGFloat {
        shadowSlack + visibilityBannerHeight - visibilityBannerOverlap
    }

    static let panelWidth: CGFloat = 1000
    static let pillGap: CGFloat = 8
    static var panelHeight: CGFloat {
        BarTooltip.reservedHeight + RecordingBarTeleprompter.height + height + bottomSlack
    }
    static let expandedCornerRadius: CGFloat = 22

    static let activeTint = Color(nsColor: .labelColor)
    static let inactiveTint = Color(nsColor: .labelColor).opacity(0.4)
    static let stroke = Color(nsColor: .separatorColor)
    static let edge = Color(nsColor: .labelColor).opacity(0.12)
    static let recordTint = Color(nsColor: .systemRed)

    static let hoverFill = Color(nsColor: .labelColor).opacity(0.11)
    static let hoverDiameter: CGFloat = 32

    static let modeChange = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

enum BarTooltip {
    static let pillHeight: CGFloat = 24
    static let gap: CGFloat = 8
    static let reservedHeight: CGFloat = gap + pillHeight + 16

    static let showDelay = Duration.milliseconds(160)
    static let warmWindow = Duration.milliseconds(500)
}

enum BarTooltipID: String {
    case display
    case window
    case area
    case areaWidth
    case areaHeight
    case areaSwap
    case areaAspect
    case camera
    case microphone
    case systemAudio
    case teleprompter
    case timer
    case close

    case pen
    case clearPen
    case pauseResume
    case restart
    case stop
    case discard
}

struct BarTooltipTarget: Equatable {
    var id: BarTooltipID
    var text: String
    var frame: CGRect
}

@Observable
@MainActor
final class BarTooltipModel {
    private(set) var visible: BarTooltipTarget?

    private var hovered: BarTooltipID?
    private var isWarm = false
    private var showTask: Task<Void, Never>?
    private var coolTask: Task<Void, Never>?

    func hover(id: BarTooltipID, text: String, frame: CGRect) {
        hovered = id
        showTask?.cancel()
        coolTask?.cancel()

        guard !isWarm else {
            visible = BarTooltipTarget(id: id, text: text, frame: frame)
            return
        }
        showTask = Task {
            try? await Task.sleep(for: BarTooltip.showDelay)
            guard !Task.isCancelled, hovered == id else { return }
            visible = BarTooltipTarget(id: id, text: text, frame: frame)
            isWarm = true
        }
    }

    func endHover(id: BarTooltipID) {
        guard hovered == id else { return }
        hovered = nil
        showTask?.cancel()
        visible = nil
        coolTask = Task {
            try? await Task.sleep(for: BarTooltip.warmWindow)
            guard !Task.isCancelled, hovered == nil else { return }
            isWarm = false
        }
    }

    func dismiss() {
        hovered = nil
        showTask?.cancel()
        withTransaction(Transaction(animation: nil)) {
            visible = nil
        }
    }
}

struct BarTooltipPill: View {
    let text: String

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(BarMetrics.activeTint)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 9)
            .frame(height: BarTooltip.pillHeight)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape.strokeBorder(BarMetrics.edge, lineWidth: 0.5)
            }
            .transition(.opacity)
    }
}

struct BarActionLabel: View {
    let id: BarTooltipID
    let title: String
    let systemImage: String
    var tint: Color = BarMetrics.activeTint
    var isSelected = false

    @Environment(\.isEnabled) private var isEnabled
    @Environment(BarTooltipModel.self) private var tooltip: BarTooltipModel?
    @State private var isHovering = false
    @State private var frame: CGRect = .zero

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(tint.opacity(isEnabled ? 1 : 0.3))
            .frame(width: BarMetrics.controlSize, height: BarMetrics.controlSize)
            .background {
                Circle()
                    .fill(BarMetrics.hoverFill)
                    .frame(
                        width: BarMetrics.hoverDiameter,
                        height: BarMetrics.hoverDiameter
                    )
                    .opacity(isHovering || isSelected ? 1 : 0)
            }
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.12), value: isSelected)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .onGeometryChange(for: CGRect.self) {
                $0.frame(in: .named(BarCoordinateSpace.bar))
            } action: {
                frame = $0
            }
            .background {
                BarControlHover(isEnabled: isEnabled, onChange: setHovering)
            }
            .onChange(of: title) { _, title in
                guard isHovering else { return }
                tooltip?.hover(id: id, text: title, frame: frame)
            }
            .onDisappear {
                tooltip?.endHover(id: id)
            }
    }

    private func setHovering(_ hovering: Bool) {
        guard hovering != isHovering else { return }
        isHovering = hovering
        if hovering {
            tooltip?.hover(id: id, text: title, frame: frame)
        } else {
            tooltip?.endHover(id: id)
        }
    }
}

struct BarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

struct BarActionButton: View {
    let id: BarTooltipID
    let title: String
    let systemImage: String
    var tint: Color = BarMetrics.activeTint
    var isSelected = false
    var accessibility: String?
    let action: () -> Void

    @Environment(BarTooltipModel.self) private var tooltip: BarTooltipModel?

    var body: some View {
        Button {
            tooltip?.dismiss()
            action()
        } label: {
            BarActionLabel(id: id, title: title, systemImage: systemImage, tint: tint, isSelected: isSelected)
        }
        .buttonStyle(BarButtonStyle())
        .accessibilityLabel(accessibility ?? title)
    }
}

struct BarDivider: View {
    var body: some View {
        Rectangle()
            .fill(BarMetrics.stroke)
            .frame(width: 1, height: 24)
            .padding(.horizontal, 5)
    }
}

enum BarCoordinateSpace {
    static let bar = "recordingBar"
    static let panel = "recordingBarPanel"
}

struct BarControlHover: NSViewRepresentable {
    let isEnabled: Bool
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> BarControlHoverView {
        let view = BarControlHoverView()
        view.onChange = onChange
        view.isTrackingEnabled = isEnabled
        return view
    }

    func updateNSView(_ view: BarControlHoverView, context: Context) {
        view.onChange = onChange
        view.isTrackingEnabled = isEnabled
    }

    static func dismantleNSView(_ view: BarControlHoverView, coordinator: ()) {
        view.endHover()
    }
}

final class BarControlHoverView: NSView {
    var onChange: ((Bool) -> Void)?
    var isTrackingEnabled = true {
        didSet {
            if !isTrackingEnabled {
                endHover()
            }
        }
    }

    private var isHovering = false

    private static weak var hovered: BarControlHoverView?

    static func endActiveHover() {
        hovered?.endHover()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        beginHover()
    }

    override func mouseMoved(with event: NSEvent) {
        beginHover()
    }

    override func mouseExited(with event: NSEvent) {
        endHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            endHover()
        }
    }

    private func beginHover() {
        guard isTrackingEnabled, !isHovering else { return }
        isHovering = true
        Self.hovered = self
        onChange?(true)
    }

    func endHover() {
        guard isHovering else { return }
        isHovering = false
        if Self.hovered === self { Self.hovered = nil }
        onChange?(false)
    }
}

struct BarDragHandle: View {
    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                GridRow {
                    dot
                    dot
                }
            }
        }
        .frame(width: 16, height: BarMetrics.controlSize)
        .contentShape(Rectangle())
        .overlay { BarDragHandleRegion() }
        .help("Drag to move")
        .accessibilityLabel("Move bar")
    }

    private var dot: some View {
        Circle()
            .fill(BarMetrics.inactiveTint)
            .frame(width: 3, height: 3)
    }
}

private struct BarDragHandleRegion: NSViewRepresentable {
    func makeNSView(context: Context) -> BarDragHandleView { BarDragHandleView() }
    func updateNSView(_ nsView: BarDragHandleView, context: Context) {}
}

final class BarDragHandleView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override var mouseDownCanMoveWindow: Bool { true }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .openHand)
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.closedHand.push()
        window?.performDrag(with: event)
        NSCursor.pop()
    }
}
