import AppKit
import ScreenCaptureKit

struct AreaCaptureWindowSnapshot {
    let image: CGImage
    let scale: CGFloat
    let presentationTime: TimeInterval?
    let requestTime: TimeInterval

    static func configuration(includeShadow: Bool) -> SCScreenshotConfiguration {
        let configuration = SCScreenshotConfiguration()
        configuration.ignoreShadows = !includeShadow
        configuration.includeChildWindows = false
        configuration.showsCursor = false
        configuration.dynamicRange = .sdr
        return configuration
    }

    static func capture(window: SCWindow, includeShadow: Bool, eventTime: TimeInterval? = nil) async throws -> AreaCaptureWindowSnapshot {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = configuration(includeShadow: includeShadow)
        let requestTime = ProcessInfo.processInfo.systemUptime
        if let eventTime {
            NSLog("Area window screenshot requested: window=%u shadow=%d selectionToRequestMs=%.3f",
                  window.windowID, includeShadow, (requestTime - eventTime) * 1000)
        }
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage else { throw CocoaError(.fileReadCorruptFile) }
        return AreaCaptureWindowSnapshot(image: image, scale: CGFloat(filter.pointPixelScale), presentationTime: nil, requestTime: requestTime)
    }

    func logTiming(windowID: CGWindowID, shadow: Bool, eventTime: TimeInterval, acquisition: String) {
        let completed = (ProcessInfo.processInfo.systemUptime - eventTime) * 1000
        if let presentationTime {
            NSLog("Area capture timing: acquisition=%@ window=%u shadow=%d selectionToFrameMs=%.3f selectionToComposedMs=%.3f",
                  acquisition, windowID, shadow, (presentationTime - eventTime) * 1000, completed)
        } else {
            NSLog("Area capture timing: acquisition=%@ window=%u shadow=%d selectionToFrameMs=unavailable selectionToRequestMs=%.3f selectionToComposedMs=%.3f",
                  acquisition, windowID, shadow, (requestTime - eventTime) * 1000, completed)
        }
    }
}
