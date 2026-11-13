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
                AppLog.event("annotation", "annotation_highlighter_recognition_completed", fields: ["boxes": String(describing: boxes.count)])
                return boxes
            } catch {
                AppLog.event("annotation", "annotation_highlighter_recognition_failed", fields: ["error": AppLog.error(error)])
                return []
            }
        }.value
    }
}
