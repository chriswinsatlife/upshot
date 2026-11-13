import AVFoundation

nonisolated enum RecordingAudioChannels {
    static func decodedSettings(mono: Bool) -> [String: Any]? {
        guard mono else { return nil }
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
    }
}
