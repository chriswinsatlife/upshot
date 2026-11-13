import AppKit
import SwiftUI

enum AnnotationEditorFocusedField: Hashable {
    case watermarkText
}

private enum AnnotationInspectorAdvancedSection: String, Hashable, CaseIterable {
    case camera
}

private enum AnnotationInspectorSectionState {
    static let expandedSectionsKey = "annotationInspector.expandedAdvancedSections"

    static func loadExpandedSections() -> Set<AnnotationInspectorAdvancedSection> {
        let rawValues = UpshotStorage.defaults.stringArray(forKey: expandedSectionsKey) ?? []
        return Set(rawValues.compactMap(AnnotationInspectorAdvancedSection.init(rawValue:)))
    }

    static func saveExpandedSections(_ sections: Set<AnnotationInspectorAdvancedSection>) {
        UpshotStorage.defaults.set(sections.map(\.rawValue), forKey: expandedSectionsKey)
    }
}

struct AnnotationEditorInspector: View {
    @Bindable var model: AnnotationEditorModel
    @Bindable var wallpaperStore: AnnotationWallpaperStore
    @Bindable var backgroundPresetStore: AnnotationBackgroundPresetStore
    let focusedField: FocusState<AnnotationEditorFocusedField?>.Binding
    let onEditorAction: () -> Void
    let onPickWallpaper: () -> Void

    static let columnMinimumWidth: CGFloat = 300
    static let columnIdealWidth: CGFloat = 320

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion
    @State private var expandedAdvancedSections: Set<AnnotationInspectorAdvancedSection> = AnnotationInspectorSectionState.loadExpandedSections()

    var body: some View {
        InterfaceFormPage {
            AnnotationStyleStrip(
                model: model,
                presetStore: backgroundPresetStore,
                onEditorAction: onEditorAction
            )

            if model.hasInspectorStyleControls {
                InterfaceSection("Annotation", detail: selectionDetail) {
                    styleControls
                }
            }

            InterfaceSection("Canvas") {
                InterfaceToggleRow("Expand automatically", isOn: Binding(
                    get: { model.automaticallyExpandsCanvas },
                    set: { model.setAutomaticallyExpandsCanvas($0) }
                ))
                InterfacePickerRow("Aspect ratio", selection: Binding(
                    get: { model.backgroundSettings.aspectRatio },
                    set: { ratio in
                        onEditorAction()
                        model.backgroundSettings.aspectRatio = ratio
                    }
                )) {
                    ForEach(AnnotationBackgroundAspectRatio.allCases) { ratio in
                        Text(ratio.title).tag(ratio)
                    }
                }
                .disabled(!model.backgroundSettings.usesCanvasLayout)
            }

            Section {
                AnnotationFrameInspector(
                    settings: Binding(
                        get: { model.backgroundSettings },
                        set: { model.backgroundSettings = $0 }
                    ),
                    wallpaperStore: wallpaperStore,
                    onEditorAction: onEditorAction,
                    onPickWallpaper: onPickWallpaper,
                    onPreview: { model.previewBackground($0, isHovering: $1) },
                    onEndPreview: { model.previewBackground = nil }
                )
            } header: {
                sectionHeader("Frame") {
                    if !usesDefaultFrame {
                        resetButton("Reset padding, corners, shadow, and alignment") {
                            let defaults = AnnotationBackgroundSettings()
                            model.backgroundSettings.padding = defaults.padding
                            model.backgroundSettings.cornerRadius = defaults.cornerRadius
                            model.backgroundSettings.shadow = defaults.shadow
                            model.backgroundSettings.shadowStyle = defaults.shadowStyle
                            model.backgroundSettings.alignment = defaults.alignment
                        }
                    }
                }
            }

            Section {
                featureRow(
                    "Border",
                    isOn: featureBinding(\.border.isEnabled),
                    showsReset: model.backgroundSettings.border.isEnabled
                        && model.backgroundSettings.border != AnnotationScreenshotBorderSettings(),
                    resetHelp: "Reset border"
                ) {
                    var border = AnnotationScreenshotBorderSettings()
                    border.isEnabled = true
                    model.backgroundSettings.border = border
                }
                if model.backgroundSettings.border.isEnabled {
                    AnnotationScreenshotBorderInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.border },
                            set: { model.backgroundSettings.border = $0 }
                        ),
                        onEditorAction: onEditorAction
                    )
                }
            }

            Section {
                let isCameraExpanded = expansionBinding(for: .camera)
                InterfaceRow(
                    "Camera",
                    detail: isCameraExpanded.wrappedValue
                        ? nil
                        : AnnotationInspectorSummary.camera(model.backgroundSettings.camera)
                ) {
                    if !model.backgroundSettings.camera.isDefault {
                        resetButton("Reset camera") {
                            model.backgroundSettings.camera = AnnotationCameraSettings()
                        }
                    }
                    AnnotationInspectorDisclosureButton(title: "Camera", isExpanded: isCameraExpanded)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(accessibilityReduceMotion ? nil : .fold) {
                        isCameraExpanded.wrappedValue.toggle()
                    }
                }
                if isCameraExpanded.wrappedValue {
                    AnnotationCameraInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.camera },
                            set: { model.backgroundSettings.camera = $0 }
                        ),
                        onEditorAction: onEditorAction
                    )
                }
            }

            Section {
                featureRow(
                    "Progressive blur",
                    isOn: featureBinding(\.progressiveBlur.isEnabled),
                    showsReset: model.backgroundSettings.progressiveBlur.isEnabled
                        && model.backgroundSettings.progressiveBlur != AnnotationProgressiveBlurSettings(),
                    resetHelp: "Reset progressive blur"
                ) {
                    var blur = AnnotationProgressiveBlurSettings()
                    blur.isEnabled = true
                    model.backgroundSettings.progressiveBlur = blur
                }
                if model.backgroundSettings.progressiveBlur.isEnabled {
                    AnnotationProgressiveBlurInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.progressiveBlur },
                            set: { model.backgroundSettings.progressiveBlur = $0 }
                        ),
                        onEditorAction: onEditorAction
                    )
                }
            }

            AnnotationColorAdjustmentInspector(
                settings: $model.backgroundSettings.colorAdjustments,
                onEditorAction: onEditorAction
            )

            Section {
                featureRow(
                    "Watermark",
                    isOn: featureBinding(\.watermark.isEnabled),
                    showsReset: model.backgroundSettings.watermark.isEnabled
                        && model.backgroundSettings.watermark != AnnotationWatermarkSettings(),
                    resetHelp: "Reset watermark"
                ) {
                    var watermark = AnnotationWatermarkSettings()
                    watermark.isEnabled = true
                    model.backgroundSettings.watermark = watermark
                }
                if model.backgroundSettings.watermark.isEnabled {
                    AnnotationWatermarkInspector(
                        settings: Binding(
                            get: { model.backgroundSettings.watermark },
                            set: { model.backgroundSettings.watermark = $0 }
                        ),
                        focusedField: focusedField,
                        onFocusCleared: onEditorAction
                    )
                }
            }
        }
        .inspectorColumnWidth(
            min: Self.columnMinimumWidth,
            ideal: Self.columnIdealWidth,
            max: InspectorMetrics.columnMaxWidth
        )
        .frame(
            minWidth: Self.columnMinimumWidth,
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
    }

    private var selectionDetail: String? {
        model.selectionCount > 1 ? "\(model.selectionCount) selected" : nil
    }

    private var usesDefaultFrame: Bool {
        let settings = model.backgroundSettings
        let defaults = AnnotationBackgroundSettings()
        return settings.padding == defaults.padding
            && settings.cornerRadius == defaults.cornerRadius
            && settings.shadow == defaults.shadow
            && settings.shadowStyle == defaults.shadowStyle
            && settings.alignment == defaults.alignment
    }

    private func sectionHeader<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: Space.s) {
            InterfaceSectionHeader(title)
            Spacer(minLength: 0)
            accessory()
        }
    }

    private func featureRow(
        _ title: String,
        isOn: Binding<Bool>,
        showsReset: Bool,
        resetHelp: String,
        reset: @escaping () -> Void
    ) -> some View {
        InterfaceRow(title) {
            if showsReset {
                resetButton(resetHelp, reset: reset)
            }
            InspectorToggle(title, isOn: isOn)
        }
    }

    private func resetButton(_ help: String, reset: @escaping () -> Void) -> some View {
        InterfaceResetButton(help: help) {
            onEditorAction()
            withAnimation(accessibilityReduceMotion ? nil : .canvasMove) { reset() }
        }
    }

    private func expansionBinding(
        for section: AnnotationInspectorAdvancedSection
    ) -> Binding<Bool> {
        Binding(
            get: { expandedAdvancedSections.contains(section) },
            set: { isExpanded in
                if isExpanded {
                    expandedAdvancedSections.insert(section)
                } else {
                    expandedAdvancedSections.remove(section)
                }
                AnnotationInspectorSectionState.saveExpandedSections(expandedAdvancedSections)
            }
        )
    }

    private func featureBinding(
        _ keyPath: WritableKeyPath<AnnotationBackgroundSettings, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { model.backgroundSettings[keyPath: keyPath] },
            set: { value in
                onEditorAction()
                model.backgroundSettings[keyPath: keyPath] = value
            }
        )
    }

    @ViewBuilder
    private var styleControls: some View {
        if model.isColorStyleAvailable {
            InterfaceToggleRow("Object shadow", isOn: Binding(
                get: { model.objectShadowsEnabled },
                set: { model.setObjectShadows($0) }
            ))
        }

        if model.isTextStyleAvailable {
            AnnotationTextStyleControls(model: model)
        } else {
            if model.isColorStyleAvailable {
                AnnotationSwatchRow(title: "Color", selectedSwatch: model.selectedSwatch) { swatch in
                    onEditorAction()
                    model.setSwatch(swatch)
                }
            }

            if model.isStrokeStyleAvailable {
                AnnotationStrokePicker(strokeWidth: model.strokeWidth) { strokeWidth in
                    onEditorAction()
                    model.setStrokeWidth(strokeWidth)
                }
            }

            if model.inspectedTool == .freehand {
                AnnotationInspectorSliderRow(
                    "Smoothing",
                    value: Binding(
                        get: { CGFloat(model.drawingSmoothing) },
                        set: { model.setDrawingSmoothing(Double($0)) }
                    ),
                    range: 0...1,
                    format: .percent()
                )
            }

            if model.isRedactionStyleAvailable {
                InterfacePickerRow("Style", selection: Binding(
                    get: { model.redactionKind },
                    set: { model.setRedactionKind($0) }
                )) {
                    ForEach(RedactionKind.allCases, id: \.self) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                AnnotationInspectorSliderRow(
                    "Strength",
                    value: Binding(
                        get: { model.redactionDensity },
                        set: {
                            onEditorAction()
                            model.setRedactionDensity($0)
                        }
                    ),
                    range: 0.15...1,
                    format: .percent()
                )
            }
        }
    }
}

private enum AnnotationInspectorSummary {
    static func camera(_ settings: AnnotationCameraSettings) -> String? {
        guard !settings.isDefault else { return nil }
        var parts: [String] = []
        let angles = [
            settings.tiltXDegrees, settings.tiltYDegrees, settings.rollDegrees,
            settings.rotationXDegrees, settings.rotationYDegrees
        ]
        if angles.contains(where: { abs($0) > 0.0001 }) {
            parts.append("Angled")
        }
        if abs(settings.zoom - 1) > 0.0001 {
            parts.append(InspectorValueFormat.magnification(fractionDigits: 2).displayString(for: settings.zoom))
        }
        if abs(settings.panX) > 0.0001 || abs(settings.panY) > 0.0001 {
            parts.append("Panned")
        }
        if parts.isEmpty {
            parts.append("Field of view \(InspectorValueFormat.degrees().displayString(for: settings.fieldOfViewDegrees))")
        }
        return parts.joined(separator: " · ")
    }
}

private struct AnnotationInspectorDisclosureButton: View {
    let title: String
    @Binding var isExpanded: Bool

    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    var body: some View {
        Button {
            withAnimation(accessibilityReduceMotion ? nil : .fold) {
                isExpanded.toggle()
            }
        } label: {
            Image(systemName: "chevron.right")
                .font(.system(size: IconSize.disclosureChevron, weight: .bold))
                .foregroundStyle(Palette.secondaryLabel)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .frame(width: InterfaceMetrics.resetButtonSize, height: InterfaceMetrics.resetButtonSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")
        .accessibilityLabel(isExpanded ? "Collapse \(title)" : "Expand \(title)")
    }
}
