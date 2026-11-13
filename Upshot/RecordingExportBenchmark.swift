#if DEBUG
import AppKit
import Foundation

enum RecordingExportBenchmark {
    static let argumentKey = "benchmarkExport"

    static func runIfRequested() -> Bool {
        if let path = UpshotStorage.defaults.string(forKey: "benchmarkMatteCache") {
            let session = RecordingSession(directoryURL: URL(fileURLWithPath: path).standardizedFileURL)
            Task {
                let started = CFAbsoluteTimeGetCurrent()
                await StudioCameraMatteCache.generate(cameraURL: session.cameraURL)
                let complete = StudioCameraMatteCache.isComplete(forCamera: session.cameraURL)
                print("benchmarkMatteCache seconds=\(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - started)) complete=\(complete)")
                exit(complete ? 0 : 1)
            }
            return true
        }
        guard let path = UpshotStorage.defaults.string(forKey: argumentKey) else { return false }
        let session = RecordingSession(directoryURL: URL(fileURLWithPath: path).standardizedFileURL)
        Task {
            do {
                var configuration = try await RecordingSessionRenderer.makeConfiguration(for: session)
                applyOverrides(to: &configuration.exportSettings)
                let started = CFAbsoluteTimeGetCurrent()
                let outputURL = try await RecordingStudioExporter().export(configuration) { _ in }
                let elapsed = CFAbsoluteTimeGetCurrent() - started
                let keepsOutput = UpshotStorage.defaults.bool(forKey: "benchmarkKeepOutput")
                if !keepsOutput { try? FileManager.default.removeItem(at: outputURL) }
                let settings = configuration.exportSettings
                print(
                    "benchmarkExport seconds=\(String(format: "%.2f", elapsed))"
                        + " codec=\(settings.codec.rawValue)"
                        + " fps=\(settings.effectiveFrameRate.framesPerSecond)"
                        + " motionBlur=\(settings.effectiveMotionBlurEnabled)"
                        + " canvas=\(Int(configuration.canvasSize.width))x\(Int(configuration.canvasSize.height))"
                        + (keepsOutput ? " output=\(outputURL.path)" : "")
                )
                exit(0)
            } catch {
                FileHandle.standardError.write(Data("benchmarkExport failed: \(error.localizedDescription)\n".utf8))
                exit(1)
            }
        }
        return true
    }

    private static func applyOverrides(to settings: inout VideoCompressionSettings) {
        let defaults = UpshotStorage.defaults
        if let codec = defaults.string(forKey: "benchmarkCodec").flatMap(VideoCompressionCodec.init(rawValue:)) {
            settings.codec = codec
        }
        if let frameRate = defaults.string(forKey: "benchmarkFPS").flatMap(VideoExportFrameRate.init(rawValue:)) {
            settings.frameRate = frameRate
        }
        if defaults.object(forKey: "benchmarkMotionBlur") != nil {
            settings.motionBlurEnabled = defaults.bool(forKey: "benchmarkMotionBlur")
        }
        if let resolution = defaults.string(forKey: "benchmarkResolution")
            .flatMap(VideoCompressionResolution.init(rawValue:)) {
            settings.resolution = resolution
        }
    }
}
#endif
