import AVFoundation
import Foundation

nonisolated enum RecordingTranscriptionSilence {
    static func commonIntervals(
        _ first: [RecordingTranscriptSegmentation.Silence],
        _ second: [RecordingTranscriptSegmentation.Silence]
    ) -> [RecordingTranscriptSegmentation.Silence] {
        var intervals: [RecordingTranscriptSegmentation.Silence] = []
        var firstIndex = 0
        var secondIndex = 0
        while firstIndex < first.count, secondIndex < second.count {
            let left = first[firstIndex]
            let right = second[secondIndex]
            let start = max(left.start, right.start)
            let end = min(left.end, right.end)
            if end > start { intervals.append(.init(start: start, end: end)) }
            if left.end < right.end { firstIndex += 1 } else { secondIndex += 1 }
        }
        return intervals
    }

    @concurrent
    static func detect(in url: URL, sourceTimeOffset: TimeInterval) async throws -> [RecordingTranscriptSegmentation.Silence] {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        guard format.sampleRate > 0, format.channelCount > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(max(1, format.sampleRate * 0.02))
              ) else {
            throw RecordingTranscriptionService.TranscriptionError.narrationUnreadable
        }
        var silences: [RecordingTranscriptSegmentation.Silence] = []
        var silenceStart: TimeInterval?
        var end: TimeInterval = sourceTimeOffset
        while file.framePosition < file.length {
            try Task.checkCancellation()
            let start = sourceTimeOffset + Double(file.framePosition) / format.sampleRate
            try file.read(into: buffer)
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw RecordingTranscriptionService.TranscriptionError.narrationUnreadable
            }
            end = sourceTimeOffset + Double(file.framePosition) / format.sampleRate
            var maximumMeanSquare: Double = 0
            for channel in 0..<Int(format.channelCount) {
                var sum: Double = 0
                for frame in 0..<Int(buffer.frameLength) {
                    let sample = Double(channels[channel][frame])
                    sum += sample * sample
                }
                maximumMeanSquare = max(maximumMeanSquare, sum / Double(buffer.frameLength))
            }
            if maximumMeanSquare < 0.001 {
                if silenceStart == nil { silenceStart = start }
            } else if let pending = silenceStart {
                if ((start - pending) * 1000).rounded() >= 500 {
                    silences.append(.init(start: pending, end: start))
                }
                silenceStart = nil
            }
        }
        if let pending = silenceStart, ((end - pending) * 1000).rounded() >= 500 {
            silences.append(.init(start: pending, end: end))
        }
        AppLog.event("recording", "transcription_silence_detection_completed", fields: [
            "interval_count": String(silences.count)
        ])
        return silences
    }
}
