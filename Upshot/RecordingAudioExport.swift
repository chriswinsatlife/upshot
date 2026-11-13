
import AVFoundation
import Foundation
import UniformTypeIdentifiers

nonisolated enum RecordingAudioFormat: String, CaseIterable, Identifiable, Codable, Sendable {
    case m4a
    case wav

    var id: Self { self }

    var title: String {
        switch self {
        case .m4a: "M4A"
        case .wav: "WAV"
        }
    }

    var fileExtension: String { rawValue }

    var fileType: AVFileType {
        switch self {
        case .m4a: .m4a
        case .wav: .wav
        }
    }

    var writerSettings: [String: Any] {
        switch self {
        case .m4a:
            [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192_000
            ]
        case .wav:
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 48_000,
                AVNumberOfChannelsKey: 2,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
        }
    }

    static let importContentTypes: [UTType] = [.audio, .mp3, .wav, .mpeg4Audio, .aiff]
}

nonisolated final class RecordingAudioExporter: @unchecked Sendable {
    struct Configuration: Sendable {
        let screenURL: URL
        let clipTimeline: RecordingClipTimeline
        let replacementURL: URL?
        let format: RecordingAudioFormat
        var volume: Double = 1
        var monoAudio = false
    }

    enum ExportError: LocalizedError {
        case noAudioTrack
        case writerFailed(Error?)

        var errorDescription: String? {
            switch self {
            case .noAudioTrack:
                "This recording has no audio to export."
            case .writerFailed(let error):
                error?.localizedDescription ?? "Writing the exported audio failed."
            }
        }
    }

    func export(
        _ configuration: Configuration,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let sourceAsset = AVURLAsset(url: configuration.screenURL)
        let sourceDuration = try await sourceAsset.load(.duration).seconds
        let timeline = configuration.clipTimeline.normalized(to: sourceDuration)
        let duration = timeline.duration
        guard duration >= RecordingClipSegment.minimumDuration else {
            throw VideoTrimExportError.invalidRange
        }

        let audioAsset: AVAsset = if let replacementURL = configuration.replacementURL {
            AVURLAsset(url: replacementURL)
        } else {
            try RecordingCompositionBuilder.makeAsset(
                from: sourceAsset,
                timeline: timeline,
                sourceDuration: sourceDuration
            )
        }

        let tracks = try await audioAsset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else {
            throw ExportError.noAudioTrack
        }

        let reader = try AVAssetReader(asset: audioAsset)
        reader.timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: duration, preferredTimescale: 600)
        )
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: RecordingAudioChannels.decodedSettings(mono: configuration.monoAudio))
        output.audioMix = RecordingAudioGain.makeMix(tracks: tracks, volume: configuration.volume)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let outputURL = Self.temporaryOutputURL(pathExtension: configuration.format.fileExtension)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: configuration.format.fileType)
        var settings = configuration.format.writerSettings
        if configuration.monoAudio { settings[AVNumberOfChannelsKey] = 1 }
        let input = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: settings
        )
        input.expectsMediaDataInRealTime = false
        writer.add(input)

        guard reader.startReading() else {
            throw reader.error ?? ExportError.writerFailed(nil)
        }
        guard writer.startWriting() else {
            throw ExportError.writerFailed(writer.error)
        }
        writer.startSession(atSourceTime: .zero)

        do {
            while let sampleBuffer = output.copyNextSampleBuffer() {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try Task.checkCancellation()
                    try await Task.sleep(nanoseconds: 2_000_000)
                }
                guard input.append(sampleBuffer) else {
                    throw ExportError.writerFailed(writer.error)
                }
                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
                if time.isFinite {
                    progress(min(0.98, max(0, time / duration)))
                }
            }
            if reader.status == .failed {
                throw reader.error ?? ExportError.writerFailed(nil)
            }
        } catch {
            reader.cancelReading()
            writer.cancelWriting()
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        input.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
        guard writer.status == .completed else {
            try? FileManager.default.removeItem(at: outputURL)
            throw ExportError.writerFailed(writer.error)
        }
        AppLog.event("recording", "audio_export_completed", fields: ["format": String(describing: configuration.format.rawValue), "mono": String(describing: String(configuration.monoAudio))])
        progress(1)
        return outputURL
    }

    private static func temporaryOutputURL(pathExtension: String) -> URL {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Upshot", isDirectory: true)
            .appendingPathComponent("StudioExports", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(pathExtension)
    }
}

nonisolated struct RecordingReplacementAudio {
    let url: URL
    let displayName: String
    let asset: AVURLAsset
    let track: AVAssetTrack
    let duration: TimeInterval

    static func load(url: URL, displayName: String) async -> RecordingReplacementAudio? {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first,
              let duration = try? await asset.load(.duration).seconds,
              duration.isFinite, duration > 0 else {
            return nil
        }
        return RecordingReplacementAudio(
            url: url,
            displayName: displayName,
            asset: asset,
            track: track,
            duration: duration
        )
    }
}
