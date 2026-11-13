import SwiftUI

struct AnnotationZoomControl: View {
    @Bindable var model: AnnotationEditorModel

    var body: some View {
        InterfacePanel(.pill) {
            Menu {
                Button("Zoom In") { model.zoomIn() }
                    .keyboardShortcut("+", modifiers: .command)
                    .disabled(!model.canZoomIn)
                Button("Zoom Out") { model.zoomOut() }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(!model.canZoomOut)

                Divider()

                Button("Fit Canvas") { model.fitCanvas() }
                    .keyboardShortcut("1", modifiers: .command)

                Divider()

                Button("50%") { model.setZoomPercent(50) }
                Button("100%") { model.setZoomPercent(100) }
                    .keyboardShortcut("0", modifiers: .command)
                Button("200%") { model.setZoomPercent(200) }
            } label: {
                HStack(spacing: Space.xs) {
                    InterfaceValueWithUnitLabel(value: "\(model.zoomPercent)", unit: "%", unitSpacing: .none)
                        .contentTransition(.numericText())
                    Image(systemName: "chevron.down")
                        .font(.system(size: IconSize.disclosureChevron, weight: .bold))
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .padding(.horizontal, Space.l)
                .frame(height: AnnotationToolDock.iconButtonSize)
                .contentShape(Capsule())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.pill))
            .fixedSize()
            .help("Zoom")
            .accessibilityLabel("Zoom")
            .accessibilityValue("\(model.zoomPercent)%")
        }
    }
}

struct CropResolutionBadge: View {
    let size: CGSize

    var body: some View {
        InterfacePanel(.pill) {
            InterfaceValueWithUnitLabel(
                value: "\(Int(size.width).formatted()) × \(Int(size.height).formatted())",
                unit: "px"
            )
            .contentTransition(.numericText())
            .padding(.horizontal, Space.l)
            .frame(height: AnnotationToolDock.iconButtonSize)
        }
        .fixedSize()
        .help("Crop size")
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Crop size")
    }
}

struct LowResolutionPreviewNotice: View {
    @State private var isExpanded = false

    var body: some View {
        InterfacePanel(.pill) {
            Button {
                withAnimation(.morphQuickIfAllowed) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: Space.s) {
                    Image(systemName: "info.circle")
                        .font(.system(size: IconSize.flyout, weight: .medium))
                        .foregroundStyle(Palette.secondaryLabel)
                    if isExpanded {
                        Text("Preview is downscaled. Exports keep full resolution.")
                            .font(.dsBody)
                            .foregroundStyle(Palette.label)
                            .lineLimit(1)
                            .fixedSize()
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, Space.ml + Space.xxs)
                .frame(minWidth: AnnotationToolDock.iconButtonSize, minHeight: AnnotationToolDock.iconButtonSize)
                .contentShape(Capsule())
            }
            .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.pill))
            .help("Why is this preview low resolution?")
            .accessibilityLabel("Low-resolution preview")
        }
        .fixedSize()
    }
}

struct AnnotationEditorWorkspaceBackground: View {
    private let dotSpacing: CGFloat = 18
    private let dotRadius: CGFloat = 1.15

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Palette.workspace)

            Canvas { context, size in
                var path = Path()
                let offset = dotSpacing / 2

                stride(from: offset, through: size.width, by: dotSpacing).forEach { x in
                    stride(from: offset, through: size.height, by: dotSpacing).forEach { y in
                        path.addEllipse(in: CGRect(
                            x: x - dotRadius,
                            y: y - dotRadius,
                            width: dotRadius * 2,
                            height: dotRadius * 2
                        ))
                    }
                }

                context.fill(path, with: .color(Color.secondary.opacity(0.14)))
            }
            .allowsHitTesting(false)
        }
    }
}
