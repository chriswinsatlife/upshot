import AVFoundation
import Foundation

nonisolated final class RecordingAudioTrackExport: @unchecked Sendable {
    let reader: AVAssetReader
    let output: AVAssetReaderAudioMixOutput
    let input: AVAssetWriterInput
    let title: String

    init(
        asset: AVAsset,
        track: AVAssetTrack,
        timeRange: CMTimeRange,
        volume: Double,
        mono: Bool,
        title: String,
        writer: AVAssetWriter
    ) throws {
        self.title = title
        reader = try AVAssetReader(asset: asset)
        reader.timeRange = timeRange
        output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: RecordingAudioChannels.decodedSettings(mono: mono))
        output.audioMix = RecordingAudioGain.makeMix(tracks: [track], volume: volume)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw RecordingStudioExporter.ExportError.writerFailed(nil) }
        reader.add(output)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: mono ? 1 : 2,
            AVEncoderBitRateKey: mono ? 96_000 : 192_000
        ])
        input.expectsMediaDataInRealTime = false
        let name = AVMutableMetadataItem()
        name.identifier = .commonIdentifierTitle
        name.value = title as NSString
        input.metadata = [name]
        guard writer.canAdd(input) else { throw RecordingStudioExporter.ExportError.writerFailed(nil) }
        writer.add(input)
    }

    func pump(isCancelled: @escaping @Sendable () -> Bool) async throws {
        while let sample = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            if isCancelled() { throw RecordingStudioExporter.ExportError.cancelled }
            while !input.isReadyForMoreMediaData {
                try Task.checkCancellation()
                if isCancelled() { throw RecordingStudioExporter.ExportError.cancelled }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard input.append(sample) else { throw RecordingStudioExporter.ExportError.writerFailed(nil) }
        }
        if reader.status == .failed { throw reader.error ?? RecordingStudioExporter.ExportError.writerFailed(nil) }
        input.markAsFinished()
        AppLog.event("recording", "separate_audio_track_completed")
    }
}
