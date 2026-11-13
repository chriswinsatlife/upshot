import AppKit
import Foundation

extension AnnotationEditorModel {
    func transformImage(_ operation: AnnotationImageTransform) async {
        guard !isProcessingImage, !isCommitting, !isCropping, let url = baseImageURL else { return }
        commitTextEditing()
        guard let snapshot = currentCropSnapshot() else {
            errorMessage = "Unable to preserve the image for undo."
            return
        }
        isProcessingImage = true
        defer { isProcessingImage = false }
        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try AnnotationImageFileProcessor.transform(url, operation: operation)
            }.value
            guard baseImageURL == url else {
                try? FileManager.default.removeItem(at: result.url)
                return
            }
            let transform = operation.pageTransform(for: imageSize)
            let matrix = Mat(transform.a, transform.b, transform.c, transform.d, transform.tx, transform.ty)
            let transformedShapes = shapes.map { original in
                var shape = original
                let result = Mat.multiply(matrix, original.pageTransform)
                shape.x = result.e
                shape.y = result.f
                shape.rotation = atan2(result.b, result.a)
                shape.isVerticallyFlipped = result.a * result.d - result.b * result.c < 0
                return shape
            }
            installImageResult(result, snapshot: snapshot, shapes: transformedShapes)
            NSLog("Annotation image transform completed operation=%@ width=%.0f height=%.0f", operation.rawValue, imageSize.width, imageSize.height)
        } catch {
            errorMessage = "Image transform failed: \(error.localizedDescription)"
            NSLog("Annotation image transform failed operation=%@ error=%@", operation.rawValue, error.localizedDescription)
        }
    }

    func installImageResult(_ result: AnnotationImageFileProcessor.Result, snapshot: CropSnapshot, shapes: [AnnoShape]) {
        let bindings = engine.document.bindings
        baseImageURL = result.url
        ownedCropURLs.insert(result.url)
        imageSize = result.size
        previewImage = makePreviewImage(from: result.url)
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        engine.viewport = AnnoViewport(imageFrame: engine.viewport.imageFrame, imageSize: imageSize)
        engine.replaceDocument(shapes: shapes, bindings: bindings)
        cropUndoStack.append(snapshot)
        cropRedoStack.removeAll()
        resetZoom()
        errorMessage = nil
    }
}
