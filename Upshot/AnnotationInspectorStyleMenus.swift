
import AppKit
import SwiftUI

struct AnnotationSwatchStrip: View {
    let selectedSwatch: AnnotationSwatch
    let onSelect: (AnnotationSwatch) -> Void

    private static let swatchDiameter: CGFloat = 17
    private static let edgeFadeWidth: CGFloat = 16
    private static let customWellID = "custom-well"

    @State private var edgeOverflow = EdgeOverflow(leading: 0, trailing: 0)

    private struct EdgeOverflow: Equatable {
        var leading: CGFloat
        var trailing: CGFloat
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedSwatch.title)
                .font(.inspectorLabel)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Selected color: \(selectedSwatch.title)")
            ScrollViewReader { scrollProxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 3) {
                    ForEach(AnnotationSwatch.allCases) { swatch in
                        swatchButton(for: swatch)
                            .id(swatch.id)
                    }

                    customWell
                        .id(Self.customWellID)
                }
            }
            .onScrollGeometryChange(for: EdgeOverflow.self) { geometry in
                EdgeOverflow(
                    leading: max(0, geometry.contentOffset.x + geometry.contentInsets.leading),
                    trailing: max(
                        0,
                        geometry.contentSize.width
                            - geometry.containerSize.width
                            - geometry.contentOffset.x
                    )
                )
            } action: { _, newValue in
                edgeOverflow = newValue
            }
            .mask(edgeFadeMask)
            .onAppear {
                scrollProxy.scrollTo(
                    isCustomSelected ? Self.customWellID : selectedSwatch.id
                )
            }
        }
            }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var edgeFadeMask: some View {
        HStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(1 - fadeStrength(for: edgeOverflow.leading)),
                    .black
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.edgeFadeWidth)

            Rectangle().fill(.black)

            LinearGradient(
                colors: [
                    .black,
                    .black.opacity(1 - fadeStrength(for: edgeOverflow.trailing))
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: Self.edgeFadeWidth)
        }
    }

    private func fadeStrength(for overflow: CGFloat) -> CGFloat {
        min(max(overflow / Self.edgeFadeWidth, 0), 1)
    }

    private func swatchButton(for swatch: AnnotationSwatch) -> some View {
        Button {
            onSelect(swatch)
            AppLog.event("annotation", "annotation_color_selected", fields: ["name": String(describing: swatch.title)])
        } label: {
            VStack(spacing: 3) {
                swatchCircle(
                    fill: AnyShapeStyle(swatch.color),
                    isSelected: selectedSwatch == swatch
                )
                Text(swatch.title)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 42)
        }
        .buttonStyle(.plain)
        .help(swatch.title)
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(selectedSwatch == swatch ? .isSelected : [])
    }

    private var customWell: some View {
        Button {
            AnnotationColorPanelBridge.shared.present(
                current: selectedSwatch.nsColor
            ) { color in
                let swatch = AnnotationSwatch.custom(from: color)
                onSelect(swatch)
                AppLog.event("annotation", "annotation_color_selected", fields: ["name": String(describing: swatch.title)])
            }
        } label: {
            VStack(spacing: 3) {
                swatchCircle(
                fill: isCustomSelected
                    ? AnyShapeStyle(selectedSwatch.color)
                    : AnyShapeStyle(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                      )),
                isSelected: isCustomSelected
                )
                Text("Custom")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 42)
        }
        .buttonStyle(.plain)
        .help("Custom color")
        .accessibilityLabel("Custom color")
        .accessibilityAddTraits(isCustomSelected ? .isSelected : [])
    }

    private func swatchCircle(fill: AnyShapeStyle, isSelected: Bool) -> some View {
        Circle()
            .fill(fill)
            .frame(width: Self.swatchDiameter, height: Self.swatchDiameter)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
            .padding(2.5)
            .overlay {
                if isSelected {
                    Circle().strokeBorder(InspectorControlPalette.selectionRing, lineWidth: 2)
                }
            }
            .contentShape(Circle().inset(by: -2))
    }

    private var isCustomSelected: Bool {
        !AnnotationSwatch.allCases.contains(selectedSwatch)
    }
}

struct AnnotationStrokePicker: View {
    let strokeWidth: CGFloat
    let onSelect: (CGFloat) -> Void

    private static let widths: [CGFloat] = [2, 4, 6, 8, 12]

    var body: some View {
        InspectorSegmented(
            options: Self.widths,
            isSelected: { $0 == strokeWidth },
            onTap: onSelect,
            label: { width in
                Circle()
                    .frame(width: dotDiameter(for: width), height: dotDiameter(for: width))
                    .help("\(Int(width)) px")
                    .accessibilityLabel("\(Int(width)) pixels")
            },
            height: InspectorMetrics.controlHeight
        )
    }

    private func dotDiameter(for width: CGFloat) -> CGFloat {
        min(width + 2, 13)
    }
}

@MainActor
final class AnnotationColorPanelBridge: NSObject {
    static let shared = AnnotationColorPanelBridge()

    private var onChange: ((NSColor) -> Void)?

    func present(current: NSColor, onChange: @escaping (NSColor) -> Void) {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = current
        self.onChange = onChange
        panel.setTarget(self)
        panel.setAction(#selector(colorDidChange(_:)))
        panel.makeKeyAndOrderFront(nil)
    }

    @objc private func colorDidChange(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}
