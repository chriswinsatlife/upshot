@preconcurrency import AVFoundation
import CoreGraphics
import FoundationModels
import ImageIO
import Vision

nonisolated enum CaptureLibraryAnalyzer {
    struct Result: Sendable {
        var analysis: CaptureAnalysis
        var featurePrint: Data?
    }

    private static let readingSize = 3200
    private static let promptTextLimit = 1800
    private static let promptTranscriptLimit = 600

    static func read(_ item: CaptureLibraryItem, previous: CaptureAnalysis?) async -> Result? {
        let frames: [CGImage]
        do {
            frames = try await readFrames(item)
        } catch is CancellationError {
            return nil
        } catch {
            NSLog("Capture Library capture failed: id=%@ error=%@", item.id, String(describing: error))
            return nil
        }
        guard let primary = frames.first else { return nil }
        guard !Task.isCancelled else { return nil }

        var lines: [CaptureTextLine] = []
        do {
            var seen = Set<String>()
            for (index, frame) in frames.enumerated() {
                try Task.checkCancellation()
                let recognized = try await ImageTextRecognizer.recognizeLines(in: frame, requiresBounds: true)
                for line in recognized where index == 0 || seen.insert(line.text).inserted {
                    lines.append(CaptureTextLine(text: line.text, box: index == 0 ? line.bounds : nil))
                    seen.insert(line.text)
                }
            }
        } catch is CancellationError {
            return nil
        } catch {
            NSLog("Capture Library text recognition failed: id=%@ error=%@", item.id, String(describing: error))
            return nil
        }
        guard !Task.isCancelled else { return nil }
        NSLog("Capture Library text recognition completed: id=%@ lines=%ld", item.id, lines.count)

        let featurePrint = try? makeFeaturePrint(of: primary)
        var analysis = CaptureAnalysis(id: item.id, fingerprint: item.thumbnailKey)
        analysis.lines = CaptureTextLines(lines)
        analysis.transcript = item.session.flatMap(transcript)
        analysis.hasFeaturePrint = featurePrint != nil
        if let previous, previous.classifier == .model {
            analysis.category = previous.category
            analysis.title = previous.title
            analysis.keywords = previous.keywords
            analysis.classifier = .model
        } else {
            analysis.category = CaptureCategoryRules.category(source: item.source, text: analysis.text, isVideo: item.isVideo)
            analysis.classifier = .rules
        }
        return Result(analysis: analysis, featurePrint: featurePrint)
    }

    static func sort(_ analysis: CaptureAnalysis, item: CaptureLibraryItem) async -> CaptureAnalysis {
        var analysis = analysis
        let image: CGImage?
        do {
            image = try await readFrames(item, framesForVideo: 1).first
        } catch is CancellationError {
            return analysis
        } catch {
            NSLog("Capture Library capture failed during classification: id=%@ error=%@", item.id, String(describing: error))
            image = nil
        }
        await classify(&analysis, item: item, image: image)
        return analysis
    }

    static var isModelAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }


    private static func readFrames(_ item: CaptureLibraryItem, framesForVideo: Int = 3) async throws -> [CGImage] {
        if item.isVideo {
            let asset = AVURLAsset(url: item.fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 1920, height: 1920)
            let tolerance = CMTime(seconds: 1, preferredTimescale: 600)
            generator.requestedTimeToleranceBefore = tolerance
            generator.requestedTimeToleranceAfter = tolerance
            let duration = item.duration ?? 0
            let fractions = [0, 0.5, 0.9].prefix(duration > 2 ? framesForVideo : 1)
            var frames: [CGImage] = []
            for fraction in fractions {
                try Task.checkCancellation()
                let time = CMTime(seconds: duration * fraction, preferredTimescale: 600)
                frames.append(try await generator.image(at: time).image)
            }
            return frames
        }
        guard let source = CGImageSourceCreateWithURL(item.fileURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: readingSize
              ] as CFDictionary) else { throw TextRecognitionError.imageUnavailable }
        return [image]
    }


    private static func makeFeaturePrint(of image: CGImage) throws -> Data? {
        let request = VNGenerateImageFeaturePrintRequest()
        try VNImageRequestHandler(cgImage: image).perform([request])
        guard let observation = request.results?.first else { return nil }
        return try NSKeyedArchiver.archivedData(withRootObject: observation, requiringSecureCoding: true)
    }

    private static func transcript(_ session: RecordingSession) -> String? {
        struct Captions: Decodable {
            struct Cue: Decodable { var text: String }
            var subtitleCues: [Cue]?
        }
        for url in [session.draftDocumentURL, session.editDocumentURL] {
            guard let data = try? Data(contentsOf: url),
                  let cues = (try? JSONDecoder().decode(Captions.self, from: data))?.subtitleCues,
                  !cues.isEmpty else { continue }
            return cues.map(\.text).joined(separator: " ")
        }
        return nil
    }


    @Generable
    struct Insight {
        @Guide(description: "The one category that best describes what the capture shows.")
        var category: Category
        @Guide(description: "A specific title of two to six words for what the capture shows, such as 'Stripe payout settings' or 'Swift build error in Xcode'. Plain words, no quotes or trailing period.")
        var title: String
        @Guide(description: "Lowercase search keywords for topics, products, people or document types the capture is about.", .maximumCount(5))
        var keywords: [String]
    }

    @Generable
    enum Category {
        case code, design, website, document, chat, email, data, error, receipt, social, media, settings, other
    }

    private static let instructions = """
        You file screenshots and screen recordings in a person's capture library so they can find them later. \
        You are given the app a capture came from, its window title and the text recognized in it. \
        Describe only what the details support; never invent names, numbers or products.
        """

    private static func classify(_ analysis: inout CaptureAnalysis, item: CaptureLibraryItem, image: CGImage?) async {
        let text = analysis.text
        let rules = CaptureCategoryRules.category(source: item.source, text: text, isVideo: item.isVideo)
        guard isModelAvailable, !Task.isCancelled else {
            analysis.category = rules
            analysis.classifier = .rules
            return
        }
        let prompt = promptText(analysis: analysis, item: item)
        let seenImage = visionCapable ? image : nil
        var insight = await respond(prompt: prompt, image: seenImage)
        if insight == nil, seenImage != nil { insight = await respond(prompt: prompt, image: nil) }
        if let insight {
            analysis.category = CaptureCategory(rawValue: String(describing: insight.category)) ?? rules
            let title = insight.title.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
            analysis.title = title.isEmpty ? nil : title
            analysis.keywords = Array(Set(insight.keywords.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty })).sorted()
            analysis.classifier = .model
        } else {
            analysis.category = rules
            analysis.classifier = .rules
            analysis.modelDeclined = true
        }
    }

    private static func promptText(analysis: CaptureAnalysis, item: CaptureLibraryItem) -> String {
        var parts = ["Capture: \(item.isVideo ? "screen recording" : "screenshot")"]
        if let source = item.source {
            parts.append("App: \(source.appName)")
            if let window = source.windowTitle { parts.append("Window title: \(window)") }
        }
        let text = analysis.text
        parts.append(text.isEmpty
            ? "Text in the capture: none"
            : "Text in the capture, possibly partial:\n\(text.prefix(promptTextLimit))")
        if let transcript = analysis.transcript {
            parts.append("Narration: \(transcript.prefix(promptTranscriptLimit))")
        }
        parts.append("Categories:\n" + CaptureCategory.allCases.map { "- \($0.rawValue): \($0.guidance)" }.joined(separator: "\n"))
        return parts.joined(separator: "\n\n")
    }

    private static func respond(prompt: String, image: CGImage?) async -> Insight? {
        let session = LanguageModelSession(instructions: instructions)
        let options = GenerationOptions(temperature: 0.2)
        do {
            if #available(macOS 27.0, *), let image {
                return try await session.respond(generating: Insight.self, options: options) {
                    prompt
                    Attachment(image).label("The capture")
                }.content
            }
            return try await session.respond(to: prompt, generating: Insight.self, options: options).content
        } catch {
            return nil
        }
    }

    private static var visionCapable: Bool {
        if #available(macOS 27.0, *) {
            return SystemLanguageModel.default.capabilities.contains(.vision)
        }
        return false
    }
}
