import AppKit
import UniformTypeIdentifiers

extension AnnotationEditorModel {
    func chooseImageToCombine(_ layout: AnnotationImageCombination) {
        guard !isProcessingImage, !isCommitting, !isCropping else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = layout.title
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { await self?.combineImage(at: url, layout: layout) }
        }
    }

    func combineImage(at additionalURL: URL, layout: AnnotationImageCombination) async {
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
                try AnnotationImageFileProcessor.combine(url, with: additionalURL, layout: layout)
            }.value
            guard baseImageURL == url else {
                try? FileManager.default.removeItem(at: result.url)
                return
            }
            installImageResult(result, snapshot: snapshot, shapes: shapes)
            NSLog("Annotation combine completed layout=%@ width=%.0f height=%.0f", layout.rawValue, imageSize.width, imageSize.height)
        } catch {
            errorMessage = "Unable to combine images: \(error.localizedDescription)"
            NSLog("Annotation combine failed layout=%@ error=%@", layout.rawValue, error.localizedDescription)
        }
    }
}
