import AppKit

@MainActor
enum CaptureTextSound {
    private struct Note {
        let frequency: Double
        let startSeconds: Double
    }

    private static let sampleRate = 48_000
    private static let notes = [Note(frequency: 783.99, startSeconds: 0), Note(frequency: 1174.66, startSeconds: 0.08)]
    private static let attackSeconds = 0.004
    private static let decaySeconds = 0.18
    private static let noteGain = 0.12
    private static let detuneRangeCents = 5.0
    private static var sound: NSSound?

    static func play() {
        let started = ProcessInfo.processInfo.systemUptime
        let detuneCents = Double.random(in: -detuneRangeCents...detuneRangeCents)
        let velocity = 0.9 + Double.random(in: 0...0.1)
        guard let sound = NSSound(data: waveData(detuneCents: detuneCents, velocity: velocity)) else {
            AppLog.event("capture", "capture_text_sound_unavailable")
            return
        }
        Self.sound?.stop()
        Self.sound = sound
        let playing = sound.play()
        AppLog.event("capture", "capture_text_sound_played", fields: ["detune_cents": String(format: "%.2f", detuneCents), "milliseconds": String(format: "%.1f", (ProcessInfo.processInfo.systemUptime - started) * 1000), "playing": String(describing: playing), "velocity": String(format: "%.3f", velocity)])
    }

    static func waveData(detuneCents: Double = 0, velocity: Double = 1) -> Data {
        let pitchRatio = pow(2, detuneCents / 1200)
        let durationSeconds = (notes.map(\.startSeconds).max() ?? 0) + attackSeconds + decaySeconds
        let frameCount = Int((durationSeconds * Double(sampleRate)).rounded(.up))
        var samples = [Double](repeating: 0, count: frameCount)
        for note in notes {
            let frequency = note.frequency * pitchRatio
            let startFrame = Int(note.startSeconds * Double(sampleRate))
            for frame in startFrame..<frameCount {
                let time = Double(frame - startFrame) / Double(sampleRate)
                guard time <= attackSeconds + decaySeconds else { break }
                let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
                let triangle = 1 - 4 * abs(phase - 0.5)
                let envelope = time < attackSeconds ? time / attackSeconds : exp(log(0.0001) * (time - attackSeconds) / decaySeconds)
                samples[frame] += triangle * envelope * noteGain * velocity
            }
        }
        return pcmWave(samples)
    }

    private static func pcmWave(_ samples: [Double]) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data()
        func append<Value: FixedWidthInteger>(_ value: Value) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36 + dataSize))
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8))
        append(UInt32(16))
        append(UInt16(1))
        append(UInt16(1))
        append(UInt32(sampleRate))
        append(UInt32(sampleRate * bytesPerSample))
        append(UInt16(bytesPerSample))
        append(UInt16(16))
        data.append(contentsOf: Array("data".utf8))
        append(UInt32(dataSize))
        let pcm = samples.map { Int16((max(-1, min(1, $0)) * Double(Int16.max)).rounded()).littleEndian }
        pcm.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
