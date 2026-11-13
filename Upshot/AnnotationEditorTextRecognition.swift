import Foundation

extension AnnotationEditorModel {
    func recognizeHighlighterText() async {
        guard let url = baseImageURL else { return }
        engine.normalizedTextBoxes = []
        let boxes = await AnnotationTextBoxRecognizer.rectangles(in: url)
        guard !Task.isCancelled, baseImageURL == url else { return }
        engine.normalizedTextBoxes = boxes
        engine.notifyChanged()
    }
}
