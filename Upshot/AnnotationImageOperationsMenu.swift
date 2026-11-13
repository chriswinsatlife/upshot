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
        } label: {
            Label("Image", systemImage: "rotate.right")
        }
        .disabled(model.isCropping || model.isCommitting || model.isProcessingImage)
        .help("Rotate or flip the image")
    }
}
