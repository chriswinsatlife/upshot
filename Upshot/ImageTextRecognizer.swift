import CoreGraphics
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ImageIO
import Vision
import VisionKit

nonisolated enum TextRecognitionError: LocalizedError {
    case imageUnavailable
    case unsupportedLanguage(String)
    case enhancementFailed

    var errorDescription: String? {
        switch self {
        case .imageUnavailable: "The capture image could not be read."
        case .unsupportedLanguage(let language): "The recognition language \(language) is unavailable."
        case .enhancementFailed: "The capture could not be enhanced for text recognition."
        }
    }
}

nonisolated struct ImageTextLine: Sendable {
    let text: String
    let bounds: CGRect?
    let characterBounds: [CGRect?]

    func bounds(for range: Range<String.Index>) -> CGRect? {
        let start = text.distance(from: text.startIndex, to: range.lowerBound)
        let end = text.distance(from: text.startIndex, to: range.upperBound)
        guard start < end, end <= characterBounds.count else { return bounds }
        return characterBounds[start..<end].compactMap { $0 }.reduce(nil) { union, box in
            union.map { $0.union(box) } ?? box
        } ?? bounds
    }

    static func imageBounds(_ box: CGRect, orientation: CGImagePropertyOrientation) -> CGRect {
        let original: CGRect
        switch orientation {
        case .right:
            original = CGRect(x: 1 - box.maxY, y: box.minX, width: box.height, height: box.width)
        case .left:
            original = CGRect(x: box.minY, y: 1 - box.maxX, width: box.height, height: box.width)
        default:
            original = box
        }
        return CGRect(x: original.minX, y: 1 - original.maxY, width: original.width, height: original.height)
    }
}

nonisolated enum ImageTextRecognizer {
    private static let liveTextAnalyzer = ImageAnalyzer()
    private static let enhancementContext = CIContext(options: [.cacheIntermediates: false])

    @MainActor
    static func recognizeText(at url: URL) async -> String {
        do {
            return try await recognizeCaptureText(at: url)
        } catch is CancellationError {
            return ""
        } catch {
            NSLog("Text recognition failed for capture file: %@", String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: failureTitle(for: error), displayID: nil)
            return ""
        }
    }

    static func recognizeCaptureText(at url: URL) async throws -> String {
        let image = try await loadImage(at: url)
        return try await recognizeText(in: image)
    }

    static func recognizeText(in image: CGImage) async throws -> String {
        let options = await TextRecognitionOptions.current
        let lines = try await recognizeLines(in: image, options: options)
        let text = formattedText(lines.map(\.text), keepLineBreaks: options.keepLineBreaks)
        let codes: [DetectedCaptureCode]
        do {
            codes = try await CaptureCodeRecognizer.detect(in: image)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            NSLog("Capture code detection failed during text recognition: %@", String(describing: error))
            if text.isEmpty { throw error }
            codes = []
        }
        let detection = try CaptureCodeRecognizer.detection(codes: codes, text: text, detectLinks: options.detectLinks)
        await CaptureCodeFeedbackPresenter.shared.present(detection, displayID: nil)
        return text.isEmpty ? formattedText(codes.map(\.displayPayload), keepLineBreaks: options.keepLineBreaks) : text
    }

    static func recognizeLines(in image: CGImage, requiresBounds: Bool = false, includeCharacterBounds: Bool = false) async throws -> [ImageTextLine] {
        try await recognizeLines(in: image, options: await TextRecognitionOptions.current, requiresBounds: requiresBounds, includeCharacterBounds: includeCharacterBounds)
    }

    static func formattedText(_ lines: [String], keepLineBreaks: Bool) -> String {
        lines.joined(separator: keepLineBreaks ? "\n" : " ")
    }

    static func failureTitle(for error: Error) -> String {
        if case TextRecognitionError.imageUnavailable = error { return "Capture failed" }
        return "Text recognition failed"
    }

    @concurrent
    static func loadImage(at url: URL) async throws -> CGImage {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw TextRecognitionError.imageUnavailable
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let rawOrientation = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
        let orientation = CGImagePropertyOrientation(rawValue: rawOrientation) ?? .up
        guard orientation != .up else { return image }
        let oriented = CIImage(cgImage: image).oriented(orientation)
        guard let upright = enhancementContext.createCGImage(oriented, from: oriented.extent) else {
            throw TextRecognitionError.imageUnavailable
        }
        return upright
    }

    private static func recognizeLines(
        in image: CGImage, options: TextRecognitionOptions, requiresBounds: Bool = false, includeCharacterBounds: Bool = false
    ) async throws -> [ImageTextLine] {
        try Task.checkCancellation()
        var liveText: [ImageTextLine] = []
        if ImageAnalyzer.isSupported {
            var configuration = ImageAnalyzer.Configuration(.text)
            if !options.language.isEmpty {
                if ImageAnalyzer.supportedTextRecognitionLanguages.contains(options.language) {
                    configuration.locales = [options.language]
                } else {
                    NSLog("Text recognition Live Text skipped: selected language unavailable")
                    return try await recognizeVisionLines(in: image, options: options, includeCharacterBounds: includeCharacterBounds)
                }
            }
            do {
                let analysis = try await liveTextAnalyzer.analyze(image, orientation: .up, configuration: configuration)
                try Task.checkCancellation()
                liveText = analysis.transcript.components(separatedBy: .newlines)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    .map { ImageTextLine(text: $0, bounds: nil, characterBounds: []) }
                NSLog("Text recognition Live Text completed: %ld lines", liveText.count)
                if !liveText.isEmpty, !requiresBounds { return liveText }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                NSLog("Text recognition Live Text failed; trying Vision: %@", String(describing: error))
            }
        } else {
            NSLog("Text recognition Live Text unavailable; trying Vision")
        }
        let lines = try await recognizeVisionLines(in: image, options: options, includeCharacterBounds: includeCharacterBounds)
        return lines.isEmpty && !requiresBounds ? liveText : lines
    }

    @concurrent
    private static func recognizeVisionLines(in image: CGImage, options: TextRecognitionOptions, includeCharacterBounds: Bool) async throws -> [ImageTextLine] {
        let original = try visionLines(in: image, language: options.language, orientation: .up, includeCharacterBounds: includeCharacterBounds)
        NSLog("Text recognition Vision initial completed: %ld lines", original.count)
        if !original.isEmpty { return original }

        let enhanced = try contrastEnhancedImage(image)
        let contrast = try visionLines(in: enhanced, language: options.language, orientation: .up, includeCharacterBounds: includeCharacterBounds)
        NSLog("Text recognition contrast retry completed: %ld lines", contrast.count)
        if !contrast.isEmpty { return contrast }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        let supported = try request.supportedRecognitionLanguages()
        let languages = options.language.isEmpty
            ? ["zh-Hant", "zh-Hans", "ja-JP", "ko-KR"].filter { supported.contains($0) }
            : [options.language].filter { $0.hasPrefix("zh") || $0.hasPrefix("ja") || $0.hasPrefix("ko") }
        for language in languages {
            for orientation in [CGImagePropertyOrientation.up, .right, .left] {
                let vertical = try visionLines(in: enhanced, language: language, orientation: orientation, includeCharacterBounds: includeCharacterBounds)
                NSLog("Text recognition vertical CJK retry completed: language=%@ orientation=%u lines=%ld", language, orientation.rawValue, vertical.count)
                if !vertical.isEmpty { return vertical }
            }
        }
        NSLog("Text recognition completed: no text found")
        return []
    }

    private static func contrastEnhancedImage(_ image: CGImage) throws -> CGImage {
        let controls = CIFilter.colorControls()
        controls.inputImage = CIImage(cgImage: image)
        controls.saturation = 0
        guard let grayscale = controls.outputImage else { throw TextRecognitionError.enhancementFailed }
        let minimum = CIFilter.areaMinimum()
        minimum.inputImage = grayscale
        minimum.extent = grayscale.extent
        let maximum = CIFilter.areaMaximum()
        maximum.inputImage = grayscale
        maximum.extent = grayscale.extent
        guard let minimumImage = minimum.outputImage, let maximumImage = maximum.outputImage else {
            throw TextRecognitionError.enhancementFailed
        }
        let lower = intensity(of: minimumImage)
        let upper = intensity(of: maximumImage)
        let gain = upper - lower > 0.0001 ? 1 / (upper - lower) : 1
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = grayscale
        matrix.rVector = CIVector(x: gain, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: gain, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: gain, w: 0)
        let bias = upper - lower > 0.0001 ? -lower * gain : 0
        matrix.biasVector = CIVector(x: bias, y: bias, z: bias, w: 0)
        guard let output = matrix.outputImage,
              let enhanced = enhancementContext.createCGImage(output, from: grayscale.extent) else {
            throw TextRecognitionError.enhancementFailed
        }
        return enhanced
    }

    private static func intensity(of image: CIImage) -> CGFloat {
        var components = [Float](repeating: 0, count: 4)
        components.withUnsafeMutableBytes { buffer in
            enhancementContext.render(image, toBitmap: buffer.baseAddress!, rowBytes: 16,
                                      bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBAf,
                                      colorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        }
        return CGFloat(components[0])
    }

    private static func visionLines(in image: CGImage, language: String, orientation: CGImagePropertyOrientation, includeCharacterBounds: Bool) throws -> [ImageTextLine] {
        try Task.checkCancellation()
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = language.isEmpty
        if !language.isEmpty {
            guard try request.supportedRecognitionLanguages().contains(language) else {
                throw TextRecognitionError.unsupportedLanguage(language)
            }
            request.recognitionLanguages = [language]
        }
        try VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:]).perform([request])
        try Task.checkCancellation()
        return readingOrder(request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var characterBounds: [CGRect?] = []
            if includeCharacterBounds {
                characterBounds = text.indices.map { index in
                    do {
                        return try candidate.boundingBox(for: index..<text.index(after: index))
                            .map { ImageTextLine.imageBounds($0.boundingBox, orientation: orientation) }
                    } catch {
                        NSLog("Text recognition character bounds unavailable; using line bounds")
                        return nil
                    }
                }
            }
            return ImageTextLine(text: text, bounds: ImageTextLine.imageBounds(observation.boundingBox, orientation: orientation), characterBounds: characterBounds)
        }
    }

    static func readingOrder(_ observations: [VNRecognizedTextObservation]) -> [VNRecognizedTextObservation] {
        let topDown = observations.sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        var ordered: [VNRecognizedTextObservation] = []
        var line: [VNRecognizedTextObservation] = []
        var lineMidY: CGFloat = 0
        func flushLine() {
            ordered.append(contentsOf: line.sorted { $0.boundingBox.minX < $1.boundingBox.minX })
            line.removeAll()
        }
        for observation in topDown {
            let box = observation.boundingBox
            if !line.isEmpty, abs(box.midY - lineMidY) > box.height / 2 { flushLine() }
            if line.isEmpty { lineMidY = box.midY }
            line.append(observation)
        }
        flushLine()
        return ordered
    }
}
