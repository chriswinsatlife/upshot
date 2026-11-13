import CoreGraphics
import Foundation
import Vision

nonisolated struct DetectedCaptureCode: Identifiable, Sendable, Hashable {
    let symbology: String
    let payload: String?
    let data: Data?

    var id: String { symbology + ":" + (payload ?? data?.base64EncodedString() ?? "") }
    var title: String { symbology == VNBarcodeSymbology.qr.rawValue ? "QR Code" : "Barcode" }
    var displayPayload: String { payload ?? data?.base64EncodedString() ?? "" }
}

nonisolated struct CaptureCodeDetection: Sendable {
    var codes: [DetectedCaptureCode]
    var links: [URL]
    var isEmpty: Bool { codes.isEmpty && links.isEmpty }
}

nonisolated enum CaptureCodeRecognizer {
    @concurrent
    static func detect(in image: CGImage) async throws -> [DetectedCaptureCode] {
        try Task.checkCancellation()
        let request = VNDetectBarcodesRequest()
        request.symbologies = try request.supportedSymbologies()
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        try Task.checkCancellation()
        var seen = Set<String>()
        let codes = (request.results ?? []).compactMap { observation -> DetectedCaptureCode? in
            let code = DetectedCaptureCode(symbology: observation.symbology.rawValue,
                                           payload: observation.payloadStringValue,
                                           data: observation.payloadData)
            guard code.payload != nil || code.data != nil, seen.insert(code.id).inserted else { return nil }
            return code
        }
        NSLog("Capture code detection completed: codes=%ld", codes.count)
        return codes
    }

    static func detectedLinks(in text: String) throws -> [URL] {
        let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        var seen = Set<URL>()
        return detector.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).compactMap {
            guard let url = $0.url, seen.insert(url).inserted else { return nil }
            return url
        }
    }

    static func detection(codes: [DetectedCaptureCode], text: String, detectLinks: Bool) throws -> CaptureCodeDetection {
        guard detectLinks else { return CaptureCodeDetection(codes: codes, links: []) }
        var seen = Set<URL>()
        let links = try ([text] + codes.compactMap(\.payload)).flatMap { try detectedLinks(in: $0) }
            .filter { seen.insert($0).inserted }
        NSLog("Capture link detection completed: links=%ld", links.count)
        return CaptureCodeDetection(codes: codes, links: links)
    }
}

