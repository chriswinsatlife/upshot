import Foundation
import Vision

nonisolated enum AnnotationTextBoxRecognizer {
    static func rectangles(in url: URL) async -> [CGRect] {
        await Task.detached(priority: .utility) {
            do {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = false
                try VNImageRequestHandler(url: url).perform([request])
                let boxes = (request.results ?? []).map { observation in
                    let bounds = observation.boundingBox
                    return CGRect(x: bounds.minX, y: 1 - bounds.maxY, width: bounds.width, height: bounds.height)
                }
                NSLog("Annotation highlighter recognition completed boxes=%ld", boxes.count)
                return boxes
            } catch {
                NSLog("Annotation highlighter recognition failed error=%@", error.localizedDescription)
                return []
            }
        }.value
    }
}
