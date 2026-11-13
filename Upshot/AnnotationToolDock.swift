import SwiftUI

struct AnnotationToolDock: View {
    @Bindable var model: AnnotationEditorModel
    let onEditorAction: () -> Void
    var canCrop = true
    let onCrop: () -> Void

    static let iconButtonSize: CGFloat = 40
    static let height: CGFloat = iconButtonSize + InterfaceMetrics.floatingPanelPadding * 2
    static let bottomPadding: CGFloat = Space.l
    static let canvasReserve: CGFloat = height

    private static let groups: [[AnnotationTool]] = [
        [.select],
        [.rectangle, .filledRectangle, .ellipse, .highlight],
        [.arrow, .line, .freehand],
        [.text, .numberedCircle],
        [.pixelate, .blur],
    ]

    var body: some View {
        InterfacePanel(.panel) {
            HStack(spacing: Space.xxs) {
                ForEach(Array(Self.groups.enumerated()), id: \.offset) { index, group in
                    if index > 0 { InterfaceToolbarDivider() }
                    ForEach(group) { tool in
                        InterfaceToolbarButton(
                            tool.title,
                            systemImage: tool.systemImage,
                            isSelected: model.selectedTool == tool,
                            labelPlacement: .hidden
                        ) {
                            onEditorAction()
                            model.selectTool(tool)
                        }
                        .help(tool.shortcutKey.map { "\(tool.helpText) (\($0))" } ?? tool.helpText)
                        .accessibilityHint(tool.helpText)
                    }
                }

                additionalToolsMenu

                InterfaceToolbarDivider()

                InterfaceToolbarButton("Crop", systemImage: "crop", labelPlacement: .hidden) {
                    onEditorAction()
                    onCrop()
                }
                .help("Crop the screenshot (C)")
                .disabled(!canCrop)
            }
            .fixedSize()
        }
    }

    private var additionalToolSelected: Bool {
        model.selectedTool == .highlighter || model.selectedTool == .measure
    }

    private var additionalToolsMenu: some View {
        Menu {
            Button("Highlighter", systemImage: AnnotationTool.highlighter.systemImage) {
                onEditorAction()
                model.selectTool(.highlighter)
            }
            Button("Measure", systemImage: AnnotationTool.measure.systemImage) {
                onEditorAction()
                model.selectTool(.measure)
            }
            Divider()
            Button("Pixelate Sensitive Text", systemImage: AnnotationTool.pixelate.systemImage) {
                onEditorAction()
                model.smartRedact(using: .pixelate)
            }
            Button("Blur Sensitive Text", systemImage: AnnotationTool.blur.systemImage) {
                onEditorAction()
                model.smartRedact(using: .blur)
            }
        } label: {
            ZStack {
                if model.isSmartRedacting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: additionalToolSelected ? model.selectedTool.systemImage : "wand.and.sparkles")
                        .font(.system(size: IconSize.toolbar, weight: .regular))
                        .foregroundStyle(model.isSmartRedacting ? Palette.disabledLabel : Palette.label)
                }
            }
            .frame(width: Self.iconButtonSize, height: Self.iconButtonSize)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(InterfaceFloatingButtonStyle(isSelected: additionalToolSelected, cornerRadius: Radius.toolbarButton))
        .fixedSize()
        .disabled(model.isSmartRedacting)
        .help("Highlighter, measure, and automatic redaction")
        .accessibilityLabel("Additional annotation tools")
        .accessibilityAddTraits(additionalToolSelected ? .isSelected : [])
    }
}

private extension AnnotationTool {
    var shortcutKey: String? {
        switch self {
        case .select: "H"
        case .rectangle: "R"
        case .ellipse: "O"
        case .text: "T"
        case .line: "L"
        case .arrow: "A"
        case .pixelate: "P"
        case .blur: "B"
        case .numberedCircle: "1"
        default: nil
        }
    }
}
