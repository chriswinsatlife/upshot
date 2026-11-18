import Foundation

nonisolated enum RecordingTranscriptSegmentation {
    struct Silence: Sendable {
        var start: TimeInterval
        var end: TimeInterval
    }

    struct Segment: Sendable {
        var start: TimeInterval
        var end: TimeInterval
        var text: String
        var words: [RecordingTranscriptWord]

        var cue: RecordingSubtitleCue {
            RecordingSubtitleCue(start: start, end: end, text: text)
        }
    }

    private static let abbreviations: Set<String> = [
        "mr", "mrs", "ms", "dr", "prof", "sr", "jr", "st", "vs", "etc"
    ]
    private static let trailingClosers: Set<Character> = Set(")]}\"'”’»」』）】］｝>")

    static func segments(
        from words: [RecordingTranscriptWord],
        silences: [Silence] = []
    ) -> [Segment] {
        let longSilences = silences.filter { milliseconds(from: $0.start, to: $0.end) >= 1500 }
        let stream = words.filter { word in
            word.start.isFinite && word.end.isFinite && word.start >= 0 &&
                word.end >= word.start && !word.displayText.isEmpty &&
                !longSilences.contains { $0.start <= word.start && word.end <= $0.end }
        }.sorted { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        guard !stream.isEmpty else { return [] }

        var phrases: [Segment] = []
        var current: [RecordingTranscriptWord] = []
        for (index, word) in stream.enumerated() {
            current.append(word)
            let shouldBreak: Bool
            if index + 1 < stream.count {
                let next = stream[index + 1]
                let gap = milliseconds(from: word.end, to: next.start)
                let silenceInGap = gap > 0 && longSilences.contains {
                    $0.start < next.start && $0.end > word.end
                }
                shouldBreak = endsSentence(word.text) || gap >= 700 ||
                    silenceInGap || milliseconds(from: current[0].start, to: word.end) >= 12000
            } else {
                shouldBreak = true
            }
            if shouldBreak {
                phrases.append(segment(from: current))
                current = []
            }
        }

        var merged: [Segment] = []
        for phrase in phrases {
            if let previous = merged.last,
               milliseconds(from: previous.start, to: previous.end) < 800,
               milliseconds(from: phrase.start, to: phrase.end) < 800,
               milliseconds(from: previous.end, to: phrase.start) <= 400,
               milliseconds(from: previous.start, to: phrase.end) <= 2500,
               previous.text.utf16.count + phrase.text.utf16.count + 1 <= 80 {
                var combined = previous
                var followingWords = phrase.words
                if let first = followingWords.first,
                   let last = previous.words.last,
                   last.text.last?.isWhitespace != true,
                   first.text.first?.isWhitespace != true {
                    followingWords[0].text = " " + first.text
                }
                combined.words += followingWords
                combined.text = previous.text + " " + phrase.text
                combined.end = phrase.end
                merged[merged.count - 1] = combined
            } else {
                merged.append(phrase)
            }
        }

        for index in merged.indices {
            let start = (merged[index].start * 1000).rounded()
            let end = (merged[index].end * 1000).rounded()
            let previousEnd = index > 0 ? (merged[index - 1].end * 1000).rounded() : 0
            let nextStart = index + 1 < merged.count ? (merged[index + 1].start * 1000).rounded() : end + 160
            let leftPad = index == 0 ? min(80, start) : min(80, floor(max(0, start - previousEnd) / 2))
            let rightPad = min(80, floor(max(0, nextStart - end) / 2))
            let paddedStart = max(0, start - leftPad)
            merged[index].start = paddedStart / 1000
            merged[index].end = max(paddedStart + 1, end + rightPad) / 1000
        }
        return merged
    }

    static func merge(microphone: [Segment], system: [Segment]) -> [Segment] {
        let speech = microphone.filter { !isSoundEvent($0.text) }
        let microphoneSpans = speech.flatMap { segment in
            segment.words.isEmpty
                ? [Silence(start: segment.start, end: segment.end)]
                : segment.words.map { Silence(start: $0.start, end: $0.end) }
        }
        func overlapsMicrophone(start: TimeInterval, end: TimeInterval) -> Bool {
            microphoneSpans.contains { start < $0.end && end > $0.start }
        }
        var retainedSystem: [Segment] = []
        for source in system {
            guard overlapsMicrophone(start: source.start, end: source.end) else {
                retainedSystem.append(source)
                continue
            }
            if source.words.isEmpty {
                var spans = [Silence(start: source.start, end: source.end)]
                for microphoneSpan in microphoneSpans {
                    spans = spans.flatMap { span -> [Silence] in
                        guard microphoneSpan.end > span.start, microphoneSpan.start < span.end else {
                            return [span]
                        }
                        return [
                            Silence(start: span.start, end: min(span.end, microphoneSpan.start)),
                            Silence(start: max(span.start, microphoneSpan.end), end: span.end)
                        ].filter { $0.end > $0.start }
                    }
                }
                retainedSystem += spans.map {
                    Segment(start: $0.start, end: $0.end, text: source.text, words: [])
                }
            } else {
                var run: [RecordingTranscriptWord] = []
                for word in source.words {
                    if overlapsMicrophone(start: word.start, end: word.end) {
                        if !run.isEmpty { retainedSystem.append(segment(from: run)) }
                        run = []
                    } else {
                        run.append(word)
                    }
                }
                if !run.isEmpty { retainedSystem.append(segment(from: run)) }
            }
        }
        let events = microphone.filter { microphoneCue in
            isSoundEvent(microphoneCue.text) && !system.contains {
                microphoneCue.start < $0.end && microphoneCue.end > $0.start
            }
        }
        return (speech + events + retainedSystem).sorted {
            $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start
        }
    }

    static func endsSentence(_ text: String) -> Bool {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = trimmed.last, trailingClosers.contains(last) {
            trimmed.removeLast()
        }
        trimmed = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last, ".?!…。！？".contains(last) else { return false }
        guard last == "." else { return true }
        let core = String(trimmed.dropLast()).lowercased()
        if abbreviations.contains(core) { return false }
        return core.range(of: #"^[a-z](\.[a-z])*$"#, options: .regularExpression) == nil
    }

    private static func segment(from words: [RecordingTranscriptWord]) -> Segment {
        Segment(
            start: words[0].start,
            end: words[words.count - 1].end,
            text: words.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines),
            words: words
        )
    }

    private static func isSoundEvent(_ text: String) -> Bool {
        text.range(of: #"^(?:\s*[\[(][^\])]+[\])]\s*)+$"#, options: .regularExpression) != nil
    }

    private static func milliseconds(from start: TimeInterval, to end: TimeInterval) -> Double {
        (end * 1000).rounded() - (start * 1000).rounded()
    }
}
