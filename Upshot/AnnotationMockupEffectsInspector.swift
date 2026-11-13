import SwiftUI

struct AnnotationProgressiveBlurInspector: View {
    @Binding var settings: AnnotationProgressiveBlurSettings
    let onEditorAction: () -> Void

    var body: some View {
        InterfaceRow("Apply to") {
            InterfaceModeSwitch(
                "Apply to",
                selection: Binding(
                    get: { settings.edgeMode },
                    set: { edgeMode in
                        onEditorAction()
                        settings.edgeMode = edgeMode
                    }
                ),
                options: AnnotationProgressiveBlurEdgeMode.allCases.map {
                    InterfaceModeSwitchOption(value: $0, title: $0.title)
                }
            )
        }
        .help(settings.edgeMode == .clipped
            ? "Blur only the screenshot content inside its frame"
            : "Blur the transformed screenshot together with its background")

        InterfaceRow("Mode") {
            InterfaceModeSwitch(
                "Mode",
                selection: Binding(
                    get: { settings.mode },
                    set: { mode in
                        onEditorAction()
                        settings.mode = mode
                    }
                ),
                options: AnnotationProgressiveBlurMode.allCases.map {
                    InterfaceModeSwitchOption(value: $0, title: $0.title)
                }
            )
        }

        AnnotationInspectorSliderRow("Strength", value: binding(\.strength), range: 0...40, format: .integer)
        AnnotationInspectorSliderRow("Falloff", value: binding(\.falloff), range: 0...1, format: .decimal(fractionDigits: 2))
        AnnotationInspectorSliderRow("Focus", value: binding(\.focusSize), range: 0...1, format: .percent())
            .help(settings.edgeMode == .clipped
                ? "Choose the size of the sharp area inside the frame"
                : "Choose the size of the sharp area across the scene")
        if settings.mode == .directional {
            AnnotationInspectorSliderRow("Angle", value: binding(\.directionDegrees), range: 0...180, format: .degrees())
        }

        VStack(alignment: .leading, spacing: Space.s) {
            InterfaceRow("Focus position") {
                InterfaceValueWithUnitLabel(value: focusPositionText, unit: "%", unitSpacing: .none)
            }
            AnnotationFocusPositionPad(
                position: $settings.focusPosition,
                mode: settings.mode,
                focusSize: settings.focusSize,
                directionDegrees: settings.directionDegrees,
                onInteractionBegan: onEditorAction
            )
        }
        .padding(.bottom, Space.xs)
    }

    private var focusPositionText: String {
        let x = Int((settings.focusPosition.x * 100).rounded())
        let y = Int((settings.focusPosition.y * 100).rounded())
        return "\(x), \(y)"
    }

    private func binding(_ keyPath: WritableKeyPath<AnnotationProgressiveBlurSettings, CGFloat>) -> Binding<CGFloat> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { value in
                onEditorAction()
                settings[keyPath: keyPath] = value
            }
        )
    }
}

private struct AnnotationFocusPositionPad: View {
    @Binding var position: CGPoint
    let mode: AnnotationProgressiveBlurMode
    let focusSize: CGFloat
    let directionDegrees: CGFloat
    let onInteractionBegan: () -> Void

    @State private var isDragging = false
    @State private var isHovering = false

    var body: some View {
        GeometryReader { proxy in
            let geometry = AnnotationProgressiveBlurGeometry(
                extent: CGRect(origin: .zero, size: proxy.size),
                focusPosition: position,
                focusSize: focusSize,
                falloff: 0,
                directionDegrees: directionDegrees,
                strength: 0,
                coordinateOrigin: .topLeft
            )
            let point = geometry.focus

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .fill(isHovering ? Palette.controlHoverFill : Palette.controlFill)

                FocusPadGrid()
                    .stroke(Palette.hairline, lineWidth: 0.5)

                if mode == .radial {
                    Circle()
                        .fill(Palette.highlight.opacity(0.055))
                        .overlay {
                            Circle()
                                .stroke(Palette.highlight.opacity(0.34), lineWidth: 1)
                        }
                        .frame(
                            width: geometry.radialFocusRadius * 2,
                            height: geometry.radialFocusRadius * 2
                        )
                        .position(point)
                } else {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .fill(Palette.highlight.opacity(0.055))
                        .overlay {
                            RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                                .stroke(Palette.highlight.opacity(0.28), lineWidth: 1)
                        }
                        .frame(
                            width: hypot(proxy.size.width, proxy.size.height) * 2,
                            height: max(2, geometry.directionalFocusHalfWidth * 2)
                        )
                        .rotationEffect(.degrees(Double(directionDegrees)))
                        .position(point)
                }

                Circle()
                    .fill(Palette.highlight)
                    .frame(width: isDragging ? 12 : 10, height: isDragging ? 12 : 10)
                    .overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: Color.black.opacity(0.22), radius: 3, y: 1)
                    .position(point)
                    .animation(.snappy(duration: 0.12), value: isDragging)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .stroke(Palette.fieldStroke, lineWidth: 0.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            onInteractionBegan()
                        }
                        position = CGPoint(
                            x: min(max(value.location.x / max(proxy.size.width, 1), 0), 1),
                            y: min(max(value.location.y / max(proxy.size.height, 1), 0), 1)
                        )
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .simultaneousGesture(
                TapGesture(count: 2)
                    .onEnded {
                        onInteractionBegan()
                        withAnimation(.snappy(duration: 0.18)) {
                            position = CGPoint(x: 0.5, y: 0.5)
                        }
                    }
            )
            .onHover { isHovering = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Blur focus position")
            .accessibilityValue(
                "X \(Int(position.x * 100)), Y \(Int(position.y * 100)), size \(Int(focusSize * 100)) percent"
            )
        }
        .frame(height: 118)
        .help("Drag to move the sharp focal area. Double-click to center.")
    }

}

private struct FocusPadGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
