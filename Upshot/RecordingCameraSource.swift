import AVFoundation
import Foundation

nonisolated struct RecordingCameraSource: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case uploaded
        case removed
    }

    var kind: Kind
    var fileName: String?
    var displayName: String?

    static let removed = RecordingCameraSource(kind: .removed)

    func url(in directory: URL) -> URL? {
        guard kind == .uploaded, let fileName,
              fileName == (fileName as NSString).lastPathComponent,
              fileName != ".", fileName != "..", !fileName.isEmpty else { return nil }
        return directory.appendingPathComponent("media", isDirectory: true).appendingPathComponent(fileName)
    }

    static func resolvedURL(source: RecordingCameraSource?, session: RecordingSession?) -> URL? {
        guard let session else { return nil }
        if let source { return source.url(in: session.directoryURL) }
        return session.hasCamera ? session.cameraURL : nil
    }
}

nonisolated enum RecordingCameraAsset {
    static func load(url: URL, loopingTo duration: TimeInterval? = nil) async throws -> AVAsset {
        let asset = AVURLAsset(url: url)
        guard let source = try await asset.loadTracks(withMediaType: .video).first else {
            throw RecordingStudioExporter.ExportError.noVideoTrack
        }
        let sourceRange = try await source.load(.timeRange)
        guard sourceRange.duration.seconds.isFinite, sourceRange.duration.seconds > 0 else { throw CocoaError(.fileReadCorruptFile) }
        guard let duration else { return asset }
        guard duration.isFinite, duration > 0 else { throw CocoaError(.fileReadCorruptFile) }
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw CocoaError(.featureUnsupported)
        }
        track.preferredTransform = try await source.load(.preferredTransform)
        let end = CMTime(seconds: duration, preferredTimescale: 600_000)
        var cursor = CMTime.zero
        while cursor < end {
            try Task.checkCancellation()
            let length = CMTimeMinimum(sourceRange.duration, end - cursor)
            try track.insertTimeRange(CMTimeRange(start: sourceRange.start, duration: length), of: source, at: cursor)
            cursor = cursor + length
        }
        return composition
    }
}
