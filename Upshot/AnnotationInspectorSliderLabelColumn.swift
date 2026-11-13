import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var annotationInspectorSliderLabelWidth: CGFloat? = nil
}

enum AnnotationInspectorSliderLabelColumn {
    static func width(for titles: [String]) -> CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
        let widest = titles
            .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return widest.rounded(.up) + 1
    }
}

extension View {
    func annotationInspectorSliderLabels(_ titles: [String]) -> some View {
        environment(\.annotationInspectorSliderLabelWidth, AnnotationInspectorSliderLabelColumn.width(for: titles))
    }
}
