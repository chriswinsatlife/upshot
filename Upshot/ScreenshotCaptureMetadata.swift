import AppKit

struct ScreenshotCaptureMetadata {
    var captureType: ScreenshotOutputCaptureType
    var bounds: CGRect?
    var sourceScale: CGFloat?
    var cursor: ScreenshotCursorSnapshot?
    var skipBackgroundPreset: Bool
    var capturedAt: Date

    init(captureType: ScreenshotOutputCaptureType, bounds: CGRect? = nil, sourceScale: CGFloat? = nil,
         cursor: ScreenshotCursorSnapshot? = nil, skipBackgroundPreset: Bool = NSEvent.modifierFlags.contains(.shift),
         capturedAt: Date = Date()) {
        self.captureType = captureType
        self.bounds = bounds
        self.sourceScale = sourceScale
        self.cursor = cursor
        self.skipBackgroundPreset = skipBackgroundPreset
        self.capturedAt = capturedAt
    }
}
