import AppKit
import SwiftUI

struct AnnotationSwatchRow: View {
    let title: String
    let selectedSwatch: AnnotationSwatch
    let onSelect: (AnnotationSwatch) -> Void

    static let swatchDiameter: CGFloat = 16
    static let selectionRingInset: CGFloat = 2.5
    private static let cellSize: CGFloat = swatchDiameter + selectionRingInset * 2

    @AppStorage(UpshotPreferences.annotationShowColorNamesKey) private var showColorNames = true

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(alignment: .firstTextBaseline) {
                InterfaceRowLabel(title)
                Spacer(minLength: Space.m)
                if showColorNames {
                    Text(isCustomSelected ? "Custom" : selectedSwatch.title)
                        .font(.dsCallout)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 0) {
                ForEach(AnnotationSwatch.allCases) { swatch in
                    swatchButton(for: swatch)
                    Spacer(minLength: 0)
                }
                customWell
            }
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(selectedSwatch.title)
    }

    private func swatchButton(for swatch: AnnotationSwatch) -> some View {
        Button {
            onSelect(swatch)
            AppLog.event("annotation", "annotation_color_selected", fields: ["name": String(describing: swatch.title)])
        } label: {
            swatchCircle(fill: AnyShapeStyle(swatch.color), isSelected: selectedSwatch == swatch)
        }
        .buttonStyle(.plain)
        .help(swatch.title)
        .accessibilityLabel(swatch.title)
        .accessibilityAddTraits(selectedSwatch == swatch ? .isSelected : [])
    }

    private var customWell: some View {
        Button {
            AnnotationColorPanelBridge.shared.present(current: selectedSwatch.nsColor) { color in
                let swatch = AnnotationSwatch.custom(from: color)
                onSelect(swatch)
                AppLog.event("annotation", "annotation_color_selected", fields: ["name": String(describing: swatch.title)])
            }
        } label: {
            swatchCircle(
                fill: isCustomSelected
                    ? AnyShapeStyle(selectedSwatch.color)
                    : AnyShapeStyle(AngularGradient(
                        colors: [.red, .yellow, .green, .cyan, .blue, .purple, .red],
                        center: .center
                    )),
                isSelected: isCustomSelected
            )
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
            .overlay(Circle().strokeBorder(Palette.hairline, lineWidth: 0.5))
            .padding(Self.selectionRingInset)
            .overlay {
                Circle()
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: Self.cellSize, height: Self.cellSize)
            .contentShape(Circle())
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
        InterfacePickerRow("Stroke", selection: Binding(get: { strokeWidth }, set: onSelect)) {
            if !Self.widths.contains(strokeWidth) {
                Text("\(Int(strokeWidth.rounded())) px").tag(strokeWidth)
            }
            ForEach(Self.widths, id: \.self) { width in
                Text("\(Int(width)) px").tag(width)
            }
        }
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
