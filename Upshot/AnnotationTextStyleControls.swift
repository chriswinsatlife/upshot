import AppKit
import SwiftUI

struct AnnotationTextStyleControls: View {
    @Bindable var model: AnnotationEditorModel

    private static let maximumFontSize = 999

    var body: some View {
        InterfacePickerRow("Style", selection: $model.selectedTextStyle) {
            ForEach(AnnotationTextStyle.allCases) { style in
                Text(style.title).tag(style)
            }
        }

        InterfacePickerRow("Font", selection: $model.selectedTextFontFamily) {
            ForEach(AnnoFontFamily.allCases) { family in
                Text(family.title).tag(family)
            }
        }

        AnnotationSwatchRow(title: "Color", selectedSwatch: model.selectedSwatch) { swatch in
            model.setSwatch(swatch)
        }

        InterfaceRow("Size") {
            InterfaceValueWithUnitField(
                "Size",
                value: fontSizeBinding,
                unit: "pt",
                range: minimumFontSize...Self.maximumFontSize
            )
            Stepper("Size", value: fontSizeBinding, in: minimumFontSize...Self.maximumFontSize)
                .labelsHidden()
        }

        InterfaceToggleRow("Bold", isOn: $model.selectedTextIsBold)
        InterfaceToggleRow("Italic", isOn: $model.selectedTextIsItalic)
        InterfaceToggleRow("Underline", isOn: $model.selectedTextIsUnderline)

        InterfacePickerRow("Alignment", selection: Binding(
            get: { TextAlignmentSegment(model.selectedTextAlignment) },
            set: { model.selectedTextAlignment = $0.nsTextAlignment }
        )) {
            ForEach(TextAlignmentSegment.allCases, id: \.self) { segment in
                Label(segment.title, systemImage: segment.systemImage).tag(segment)
            }
        }
    }

    private var minimumFontSize: Int {
        Int(AnnotationTextMetrics.minimumFontSize)
    }

    private var fontSizeBinding: Binding<Int> {
        Binding(
            get: { Int(model.selectedTextFontSize.rounded()) },
            set: { size in
                model.selectedTextFontSize = CGFloat(max(size, minimumFontSize))
            }
        )
    }
}

private enum TextAlignmentSegment: CaseIterable, Hashable {
    case left
    case center
    case right
    case justified

    init(_ alignment: NSTextAlignment) {
        switch alignment {
        case .center:
            self = .center
        case .right:
            self = .right
        case .justified:
            self = .justified
        default:
            self = .left
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .left: .left
        case .center: .center
        case .right: .right
        case .justified: .justified
        }
    }

    var title: String {
        switch self {
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .justified: "Justified"
        }
    }

    var systemImage: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        case .justified: "text.justify.leading"
        }
    }
}
