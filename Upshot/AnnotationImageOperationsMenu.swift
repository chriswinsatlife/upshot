import SwiftUI

struct AnnotationImageOperationsMenu: View {
    let model: AnnotationEditorModel

    var body: some View {
        Menu {
            ForEach(AnnotationImageTransform.allCases) { operation in
                Button(operation.title) {
                    Task { await model.transformImage(operation) }
                }
            }
            Divider()
            ForEach(AnnotationImageCombination.allCases) { layout in
                Button(layout.title) { model.chooseImageToCombine(layout) }
            }
        } label: {
            Label("Image", systemImage: "rotate.right")
        }
        .disabled(model.isCropping || model.isCommitting || model.isProcessingImage)
        .help("Rotate, flip, or combine images")
    }
}
