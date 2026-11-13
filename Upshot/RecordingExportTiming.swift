import CoreGraphics
import CoreMedia
import Foundation

nonisolated struct RecordingExportTiming: Sendable {
    let framesPerSecond: Double
    let motionBlurLevel: RecordingMotionBlurLevel
    var motionBlurEnabled: Bool { motionBlurLevel != .off }

    init(settings: VideoCompressionSettings, motionBlurLevel: RecordingMotionBlurLevel? = nil, frameRateOverride: Double? = nil) {
        framesPerSecond = frameRateOverride ?? settings.effectiveFrameRate.framesPerSecond
        self.motionBlurLevel = motionBlurLevel ?? (settings.effectiveMotionBlurEnabled ? .high : .off)
    }

    var frameInterval: TimeInterval { 1 / framesPerSecond }

    func frameCount(for duration: TimeInterval) -> Int {
        max(1, Int((duration * framesPerSecond).rounded()))
    }

    func time(forFrame frame: Int) -> TimeInterval { Double(frame) / framesPerSecond }

    func presentationTime(forFrame frame: Int) -> CMTime {
        CMTime(value: Int64(frame), timescale: CMTimeScale(framesPerSecond))
    }

    func screenSampleRects(at time: TimeInterval, frameRect: (TimeInterval) -> CGRect) -> [CGRect] {
        sampleTimes(at: time, frameRect: frameRect).map(frameRect)
    }

    func sampleTimes(at time: TimeInterval, frameRect: (TimeInterval) -> CGRect) -> [TimeInterval] {
        guard motionBlurEnabled else { return [time] }

        let shutter = frameInterval * motionBlurLevel.shutterFraction
        let a = frameRect(time - shutter / 2)
        let b = frameRect(time + shutter / 2)
        let displacement = max(
            max(abs(a.minX - b.minX), abs(a.minY - b.minY)),
            max(abs(a.maxX - b.maxX), abs(a.maxY - b.maxY))
        )
        let count = displacement > 1.5 ? min(24, max(2, Int((displacement / 2).rounded(.up)))) : 1
        guard count > 1 else { return [time] }
        return (0..<count).map { sample in
            time - shutter / 2 + shutter * (Double(sample) + 0.5) / Double(count)
        }
    }
}
