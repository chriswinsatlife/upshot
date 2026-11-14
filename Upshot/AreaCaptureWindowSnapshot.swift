import AppKit
import ScreenCaptureKit

struct AreaCaptureWindowSnapshot {
    let image: CGImage
    let scale: CGFloat
    let presentationTime: TimeInterval?
    let requestTime: TimeInterval

    static func configuration(includeShadow: Bool, showsCursor: Bool = false) -> SCScreenshotConfiguration {
        let configuration = SCScreenshotConfiguration()
        configuration.ignoreShadows = !includeShadow
        configuration.includeChildWindows = false
        configuration.showsCursor = showsCursor
        configuration.dynamicRange = .sdr
        return configuration
    }

    static func capture(window: SCWindow, includeShadow: Bool, showsCursor: Bool = false, eventTime: TimeInterval? = nil) async throws -> AreaCaptureWindowSnapshot {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = configuration(includeShadow: includeShadow, showsCursor: showsCursor)
        let requestTime = ProcessInfo.processInfo.systemUptime
        if let eventTime {
            AppLog.event("capture", "area_window_screenshot_requested", fields: ["selection_to_request_ms": String(format: "%.3f", (requestTime - eventTime) * 1000), "shadow": String(describing: includeShadow), "window": String(describing: window.windowID)])
        }
        let output = try await SCScreenshotManager.captureScreenshot(contentFilter: filter, configuration: configuration)
        guard let image = output.sdrImage else { throw CocoaError(.fileReadCorruptFile) }
        return AreaCaptureWindowSnapshot(image: image, scale: CGFloat(filter.pointPixelScale), presentationTime: nil, requestTime: requestTime)
    }

    func logTiming(windowID: CGWindowID, shadow: Bool, eventTime: TimeInterval, acquisition: String) {
        let completed = (ProcessInfo.processInfo.systemUptime - eventTime) * 1000
        if let presentationTime {
            AppLog.event("capture", "area_capture_timing_measured", fields: ["acquisition": acquisition, "selection_to_composed_ms": String(format: "%.3f", completed), "selection_to_frame_ms": String(format: "%.3f", (presentationTime - eventTime) * 1000), "shadow": String(describing: shadow), "window": String(describing: windowID)])
        } else {
            AppLog.event("capture", "area_capture_timing_measured", fields: ["acquisition": acquisition, "selection_to_composed_ms": String(format: "%.3f", completed), "selection_to_frame_ms": "unavailable", "selection_to_request_ms": String(format: "%.3f", (requestTime - eventTime) * 1000), "shadow": String(describing: shadow), "window": String(describing: windowID)])
        }
    }
}
