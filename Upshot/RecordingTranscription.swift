import AVFoundation
import CoreGraphics
import Foundation
import Speech

nonisolated struct RecordingTranscriptWord: Codable, Sendable, Equatable {
    var text: String
    var start: TimeInterval
    var end: TimeInterval
    var source: RecordingTranscriptSource? = nil

    init(text: String, start: TimeInterval, end: TimeInterval, source: RecordingTranscriptSource? = nil) {
        self.text = text
        self.start = start
        self.end = end
        self.source = source
    }

    private enum CodingKeys: String, CodingKey {
        case text
        case start
        case end
        case source
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        source = try container.decodeIfPresent(RecordingTranscriptSource.self, forKey: .source)
    }

    var displayText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var midpoint: TimeInterval {
        (start + end) / 2
    }
}

nonisolated enum RecordingTranscriptSource: String, Codable, Sendable {
    case microphone
    case system
}

nonisolated struct RecordingTranscript: Sendable {
    var words: [RecordingTranscriptWord]
    var cues: [RecordingSubtitleCue]
}

/// One subtitle on the source (unedited) timeline, in seconds.
nonisolated struct RecordingSubtitleCue: Codable, Sendable, Equatable, Identifiable {
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var text: String

    init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case start
        case end
        case text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Cues saved before editing shipped carry no identity; mint one so
        // the editor's list rows stay stable for this session.
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        text = try container.decode(String.self, forKey: .text)
    }
}

// MARK: - Subtitle timeline

/// Deterministic subtitle playback: the cue covering a source time, if any.
nonisolated struct SubtitleTimeline: Sendable, Equatable {
    private let cues: [RecordingSubtitleCue]

    static let empty = SubtitleTimeline(cues: [])

    init(cues: [RecordingSubtitleCue]) {
        self.cues = cues
            .filter { $0.start.isFinite && $0.end > $0.start && !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
    }

    var isEmpty: Bool {
        cues.isEmpty
    }

    var count: Int {
        cues.count
    }

    func text(at time: TimeInterval) -> String? {
        cue(at: time)?.text
    }

    func cue(at time: TimeInterval) -> RecordingSubtitleCue? {
        guard !cues.isEmpty, time.isFinite else { return nil }

        // Last cue that has already started.
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0 else { return nil }

        let cue = cues[index]
        return time < cue.end ? cue : nil
    }
}

// MARK: - Karaoke word timing

/// Word-level state of the subtitle bar at a moment in time: the active
/// cue's words plus which one is being spoken. Shared verbatim by the
/// SwiftUI preview and the CoreGraphics exporter so highlights match.
nonisolated struct KaraokeTimeline: Sendable {
    struct Line: Equatable {
        /// Display words of the active cue, original order, trimmed.
        var words: [String]
        /// Index into `words` currently being spoken; nil between words
        /// and after the cue's last word ends.
        var activeIndex: Int?
        /// How many words have started; spoken words render fully lit
        /// even once the active highlight has moved on.
        var spokenCount: Int
    }

    private struct CueLine {
        var start: TimeInterval
        var end: TimeInterval
        /// Display words from the cue's (possibly hand-edited) text.
        var words: [String]
        /// Per-display-word timing, index-mapped from the timed words so
        /// text edits keep working even when word counts drift.
        var timings: [(start: TimeInterval, end: TimeInterval)]
    }

    private let cues: [CueLine]

    static let empty = KaraokeTimeline(cues: [], words: [])

    /// Groups timed words into cues the same way the cues were chunked
    /// from them (a word belongs to the last cue starting at or before
    /// it), but displays the cue's *text* - the editable source of truth -
    /// with timings carried over from the recognizer's words.
    init(cues: [RecordingSubtitleCue], words: [RecordingTranscriptWord]) {
        let sortedCues = cues
            .filter { $0.start.isFinite && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        var timedByCue: [[RecordingTranscriptWord]] = sortedCues.map { _ in [] }
        var cueIndex = 0
        for word in words.sorted(by: { $0.start < $1.start }) {
            while cueIndex < sortedCues.count - 1,
                  word.start >= sortedCues[cueIndex + 1].start - 0.001 {
                cueIndex += 1
            }
            if !timedByCue.isEmpty {
                timedByCue[min(cueIndex, timedByCue.count - 1)].append(word)
            }
        }

        self.cues = zip(sortedCues, timedByCue).compactMap { cue, timed in
            guard !timed.isEmpty else { return nil }
            let displayWords = cue.text
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            guard !displayWords.isEmpty else { return nil }
            let timings = displayWords.indices.map { index in
                let timedIndex = min(
                    timed.count - 1,
                    index * timed.count / displayWords.count
                )
                return (start: timed[timedIndex].start, end: timed[timedIndex].end)
            }
            return CueLine(
                start: cue.start,
                end: cue.end,
                words: displayWords,
                timings: timings
            )
        }
    }

    var isEmpty: Bool {
        cues.isEmpty
    }

    /// The karaoke line covering a source time; nil when nobody is
    /// speaking or the cue carries no word timings.
    func line(at time: TimeInterval) -> Line? {
        guard !cues.isEmpty, time.isFinite else { return nil }
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].start <= time {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let index = low - 1
        guard index >= 0, time < cues[index].end else { return nil }

        let cue = cues[index]
        var activeIndex: Int?
        var spokenCount = 0
        if let lastStarted = cue.timings.lastIndex(where: { $0.start <= time }) {
            spokenCount = lastStarted + 1
            let timing = cue.timings[lastStarted]
            // The highlight rides each word until the next one starts; on
            // the cue's last word a small bridge past its end keeps it from
            // flickering off early, after which the line reads fully spoken.
            if lastStarted < cue.timings.count - 1 || time <= timing.end + 0.25 {
                activeIndex = lastStarted
            }
        }
        return Line(
            words: cue.words,
            activeIndex: activeIndex,
            spokenCount: spokenCount
        )
    }
}

// MARK: - Subtitle bar metrics

/// Geometry shared verbatim by the SwiftUI preview and the CoreGraphics
/// exporter: a rounded black bar with white text, center-locked
/// horizontally at the style's vertical position. Everything derives from
/// the full canvas height - the bar belongs to the composition, background
/// included, not just the recording card - so it is identical at any
/// render resolution and stays put in padded or portrait layouts.
nonisolated struct SubtitleBarMetrics: Sendable {
    let fontSize: CGFloat
    let paddingHorizontal: CGFloat
    let paddingVertical: CGFloat
    let cornerRadius: CGFloat

    static let backgroundAlpha: Double = 0.78

    /// Karaoke palette, shared by preview and export: the spoken word in
    /// warm yellow, words not yet spoken slightly dimmed.
    static let karaokeAccent = CGColor(red: 1, green: 0.84, blue: 0.04, alpha: 1)
    static let karaokeUpcomingAlpha: Double = 0.55

    /// Widest the bar may grow, as a fraction of the canvas width; text
    /// that would exceed it wraps into centered lines.
    static let maximumWidthFraction: CGFloat = 0.92
    /// Wrapped lines allowed before the font starts scaling down.
    static let maximumLineCount = 3
    /// Baseline-to-baseline advance as a multiple of ascent + descent,
    /// shared by the preview's lineSpacing and the exporter's layout.
    static let lineSpacingFactor: CGFloat = 1.12

    /// Sized off the canvas's smaller dimension: identical to the old
    /// height-based sizing in landscape, and keeps the bar inside narrow
    /// portrait/square canvases.
    init(canvasSize: CGSize, style: SubtitleBarStyle = SubtitleBarStyle()) {
        let reference = min(canvasSize.width, canvasSize.height)
        fontSize = max(11, reference * 0.032 * style.clampedFontScale)
        paddingHorizontal = fontSize * 0.85
        paddingVertical = fontSize * 0.5
        cornerRadius = fontSize * 0.6
    }

    /// Room available for the text line itself on this canvas.
    func maximumTextWidth(canvasWidth: CGFloat) -> CGFloat {
        max(24, canvasWidth * Self.maximumWidthFraction - paddingHorizontal * 2)
    }
}

// MARK: - Transcription service

nonisolated enum RecordingTranscriptionService {
    enum TranscriptionError: LocalizedError {
        case noNarrationTrack
        case unsupportedLocale
        case narrationUnreadable

        var errorDescription: String? {
            switch self {
            case .noNarrationTrack:
                "This recording has no audio to transcribe."
            case .unsupportedLocale:
                "On-device transcription isn't available for your language yet."
            case .narrationUnreadable:
                "The recording audio could not be read."
            }
        }
    }

    private struct AudioSource {
        var track: AVAssetTrack
        var source: RecordingTranscriptSource?
    }

    private struct SourceTranscript: Sendable {
        var segments: [RecordingTranscriptSegmentation.Segment]
        var silences: [RecordingTranscriptSegmentation.Silence]
    }

    @concurrent
    static func transcribe(screenMovieURL: URL, localeIdentifier: String? = nil) async throws -> RecordingTranscript {
        let sources = try await audioSources(in: screenMovieURL)
        let locale = try await resolveLocale(identifier: localeIdentifier)
        var results: [SourceTranscript] = []
        for source in sources {
            try Task.checkCancellation()
            results.append(try await transcribe(source, locale: locale))
        }
        let segments = results.count == 2
            ? RecordingTranscriptSegmentation.merge(microphone: results[0].segments, system: results[1].segments)
            : results.flatMap(\.segments)
        var words = segments.flatMap(\.words).sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
        for index in words.indices where index > 0 {
            if words[index].source != words[index - 1].source,
               words[index - 1].text.last?.isWhitespace != true,
               words[index].text.first?.isWhitespace != true {
                words[index].text = " " + words[index].text
            }
        }
        let cues: [RecordingSubtitleCue]
        if results.count == 2 {
            let silences = RecordingTranscriptionSilence.commonIntervals(results[0].silences, results[1].silences)
            cues = RecordingTranscriptSegmentation.segments(from: words, silences: silences).map(\.cue)
        } else {
            cues = segments.map(\.cue)
        }
        AppLog.event("recording", "transcription_sources_merged", fields: [
            "source_count": String(sources.count),
            "word_count": String(words.count),
            "cue_count": String(cues.count)
        ])
        return RecordingTranscript(words: words, cues: cues)
    }

    private static func transcribe(
        _ source: AudioSource,
        locale: Locale
    ) async throws -> SourceTranscript {
        let extracted = try await extractAudio(from: source.track)
        defer {
            do {
                try FileManager.default.removeItem(at: extracted.url)
            } catch {
                AppLog.event("recording", "transcription_audio_cleanup_failed", fields: ["error": AppLog.error(error)])
            }
        }
        let silences: [RecordingTranscriptSegmentation.Silence]
        do {
            silences = try await RecordingTranscriptionSilence.detect(
                in: extracted.url,
                sourceTimeOffset: extracted.sourceTimeOffset
            )
        } catch {
            try Task.checkCancellation()
            AppLog.event("recording", "transcription_silence_detection_failed", fields: ["error": AppLog.error(error)])
            silences = []
        }
        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.audioTimeRange]
        )
        if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            AppLog.event("recording", "transcription_assets_installing", fields: ["locale": locale.identifier(.bcp47)])
            try await installation.downloadAndInstall()
        }
        try Task.checkCancellation()
        let audioFile = try AVAudioFile(forReading: extracted.url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        return try await withTaskCancellationHandler {
            async let collectedWords = collectWords(
                from: transcriber,
                source: source.source,
                sourceTimeOffset: extracted.sourceTimeOffset
            )
            do {
                if let lastSampleTime = try await analyzer.analyzeSequence(from: audioFile) {
                    try await analyzer.finalizeAndFinish(through: lastSampleTime)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let words = try await collectedWords
                try Task.checkCancellation()
                return SourceTranscript(
                    segments: RecordingTranscriptSegmentation.segments(from: words, silences: silences),
                    silences: silences
                )
            } catch {
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            Task { await analyzer.cancelAndFinishNow() }
        }
    }

    static func resolveLocale(identifier: String? = nil) async throws -> Locale {
        if let identifier, !identifier.isEmpty {
            guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: identifier)) else {
                throw TranscriptionError.unsupportedLocale
            }
            return locale
        }
        let supported = await SpeechTranscriber.supportedLocales
        let current = Locale.current
        if let exact = supported.first(where: {
            $0.identifier(.bcp47) == current.identifier(.bcp47)
        }) {
            return exact
        }
        if let sameLanguage = supported.first(where: {
            $0.language.languageCode == current.language.languageCode
        }) {
            return sameLanguage
        }
        if let english = supported.first(where: { $0.language.languageCode?.identifier == "en" }) {
            return english
        }
        throw TranscriptionError.unsupportedLocale
    }

    static func supportedLocales() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted {
            localeTitle($0).localizedStandardCompare(localeTitle($1)) == .orderedAscending
        }
    }

    static func localeTitle(_ locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier(.bcp47)) ?? locale.identifier(.bcp47)
    }

    private static func audioSources(in movieURL: URL) async throws -> [AudioSource] {
        let asset = AVURLAsset(url: movieURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        guard let fallback = audioTracks.last else {
            throw TranscriptionError.noNarrationTrack
        }
        var microphone: AVAssetTrack?
        var system: AVAssetTrack?
        for track in audioTracks {
            let descriptions = try await track.load(.formatDescriptions)
            let channels = descriptions.compactMap { $0.audioStreamBasicDescription?.mChannelsPerFrame }.max() ?? 0
            if channels == 1, microphone == nil { microphone = track }
            if channels > 1, system == nil { system = track }
        }
        if let microphone, let system {
            return [AudioSource(track: microphone, source: .microphone), AudioSource(track: system, source: .system)]
        }
        if let microphone { return [AudioSource(track: microphone, source: .microphone)] }
        return [AudioSource(track: system ?? fallback, source: system == nil ? nil : .system)]
    }

    private static func extractAudio(from track: AVAssetTrack) async throws -> (url: URL, sourceTimeOffset: TimeInterval) {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TranscriptionError.narrationUnreadable
        }
        let timeRange = try await track.load(.timeRange)
        guard timeRange.start.seconds.isFinite, timeRange.duration.seconds > 0 else {
            throw TranscriptionError.narrationUnreadable
        }
        try compositionTrack.insertTimeRange(timeRange, of: track, at: .zero)

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.narrationUnreadable
        }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("upshot-transcription-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        do {
            try await exportSession.export(to: outputURL, as: .m4a)
            AppLog.event("recording", "transcription_audio_extracted", fields: [
                "source_time_offset": String(timeRange.start.seconds),
                "duration": String(timeRange.duration.seconds)
            ])
            return (outputURL, timeRange.start.seconds)
        } catch {
            if FileManager.default.fileExists(atPath: outputURL.path) {
                do {
                    try FileManager.default.removeItem(at: outputURL)
                } catch {
                    AppLog.event("recording", "transcription_audio_cleanup_failed", fields: ["error": AppLog.error(error)])
                }
            }
            throw error
        }
    }

    private static func collectWords(
        from transcriber: SpeechTranscriber,
        source: RecordingTranscriptSource?,
        sourceTimeOffset: TimeInterval
    ) async throws -> [RecordingTranscriptWord] {
        var words: [RecordingTranscriptWord] = []
        for try await result in transcriber.results where result.isFinal {
            for run in result.text.runs {
                let runText = String(result.text[run.range].characters)
                if runText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    if !words.isEmpty { words[words.count - 1].text += runText }
                    continue
                }
                guard let timeRange = run.audioTimeRange else {
                    if !words.isEmpty {
                        words[words.count - 1].text += runText
                    }
                    continue
                }
                let start = sourceTimeOffset + timeRange.start.seconds
                let end = sourceTimeOffset + timeRange.end.seconds
                guard start.isFinite, end.isFinite else { continue }
                words.append(RecordingTranscriptWord(text: runText, start: start, end: max(start, end), source: source))
            }
        }
        return words
    }

    static func makeCues(from words: [RecordingTranscriptWord]) -> [RecordingSubtitleCue] {
        RecordingTranscriptSegmentation.segments(from: words).map(\.cue)
    }
}
