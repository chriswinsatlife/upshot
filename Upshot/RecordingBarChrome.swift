import AppKit
import SwiftUI

enum BarMetrics {
    static var height: CGFloat {
        InterfaceMetrics.toolbarButtonHeight + InterfaceMetrics.floatingPanelPadding * 2
    }

    static let shadowSlack: CGFloat = 28
    static let topSlack: CGFloat = 28
    static let accessoryGap: CGFloat = Space.m

    static var visibilityToastReserve: CGFloat {
        InterfaceMetrics.toastMinimumHeight + accessoryGap
    }

    static var bottomSlack: CGFloat {
        shadowSlack + visibilityToastReserve
    }

    static let panelWidth: CGFloat = 1240
    static var panelHeight: CGFloat {
        topSlack + RecordingBarTeleprompter.height + height + bottomSlack
    }

    static let modeChange = Animation.spring(response: 0.34, dampingFraction: 0.86)
}

enum BarCoordinateSpace {
    static let panel = "recordingBarPanel"
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
        .frame(width: Space.xl)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay { BarDragHandleRegion() }
        .help("Drag to move")
        .accessibilityLabel("Move bar")
    }

    private var dot: some View {
        Circle()
            .fill(Palette.tertiaryLabel)
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

struct RecordingBarMenuButton<MenuContent: View>: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var accessibility: String?
    @ViewBuilder var menuContent: () -> MenuContent

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            menuContent()
        } label: {
            VStack(spacing: InterfaceMetrics.toolbarIconToLabelSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: InterfaceMetrics.toolbarIconPointSize, weight: .regular))
                    .frame(height: 20)
                Text(title)
                    .font(.dsToolbarLabel)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
            .padding(.horizontal, Space.m)
            .frame(minWidth: InterfaceMetrics.toolbarButtonMinimumWidth, minHeight: InterfaceMetrics.toolbarButtonHeight)
            .contentShape(RoundedRectangle(cornerRadius: Radius.toolbarButton, style: .continuous))
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(InterfaceFloatingButtonStyle(isSelected: isSelected, cornerRadius: Radius.toolbarButton))
        .fixedSize()
        .help(title)
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
