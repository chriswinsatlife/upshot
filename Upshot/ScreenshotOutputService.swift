import CoreGraphics
import Foundation
import ImageIO

enum ScreenshotOutputService {
    static func processCapture(
        at url: URL,
        captureType: ScreenshotOutputCaptureType,
        appName: String,
        displayID: CGDirectDisplayID? = nil,
        captureBounds: CGRect? = nil,
        sourceScale: CGFloat? = nil,
        cursor: ScreenshotCursorSnapshot? = nil,
        skipBackgroundPreset: Bool,
        capturedAt: Date = Date()
    ) async throws -> URL {
        do {
            let options = ScreenshotPixelOptions(
                convertToSRGB: UpshotPreferences.screenshotConvertToSRGB,
                scaleToOneX: UpshotPreferences.screenshotScaleToOneX,
                addBorder: UpshotPreferences.screenshotBorder
            )
            let preset = try ScreenshotBackgroundService.presetSettings(skipPreset: skipBackgroundPreset)
            let windowBackground = captureType == .window
                ? try ScreenshotWindowBackgroundService.configuration(displayID: displayID)
                : nil
            let result = try await Task.detached(priority: .userInitiated) {
                try processPixels(
                    at: url,
                    options: options,
                    sourceScale: sourceScale,
                    cursor: cursor,
                    captureBounds: captureBounds,
                    preset: preset,
                    windowBackground: windowBackground
                )
            }.value
            try Task.checkCancellation()
            let suggested = ScreenshotFileNaming.captureFileName(
                date: capturedAt,
                appName: appName,
                captureType: captureType,
                outputScale: result.outputScale
            )
            let fileName = ScreenshotCaptureNamePrompt.fileName(suggested: suggested, outputScale: result.outputScale)
            let destination: URL
            if url.lastPathComponent == fileName {
                destination = url
            } else {
                destination = ScreenshotFileNaming.uniqueURL(fileName: fileName, in: url.deletingLastPathComponent())
                try FileManager.default.moveItem(at: url, to: destination)
            }
            NSLog("Screenshot output: capture finalized type=%@ filename=%@ width=%d height=%d scale=%.2f", captureType.rawValue, destination.lastPathComponent, result.width, result.height, result.outputScale)
            return destination
        } catch {
            NSLog("Screenshot output: processing failed type=%@ error=%@", captureType.rawValue, error.localizedDescription)
            throw error
        }
    }

    nonisolated static func processPixels(
        at url: URL,
        options: ScreenshotPixelOptions,
        sourceScale: CGFloat? = nil,
        cursor: ScreenshotCursorSnapshot? = nil,
        captureBounds: CGRect? = nil,
        preset: AnnotationBackgroundSettings? = nil,
        windowBackground: ScreenshotWindowBackground? = nil
    ) throws -> ScreenshotPixelProcessingResult {
        try autoreleasepool {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
            let scale = ScreenshotPixelProcessor.sourceScale(properties: properties, override: sourceScale)
            let outputScale: CGFloat = options.scaleToOneX ? 1 : scale
            if let cursor {
                guard let captureBounds else { throw ScreenshotOutputError.cursorBoundsMissing }
                image = try ScreenshotCursorService.composite(image: image, cursor: cursor, captureBounds: captureBounds)
            }
            image = try ScreenshotPixelProcessor.process(image: image, sourceScale: scale, options: options)
            if let windowBackground {
                image = try ScreenshotWindowBackgroundService.compose(image: image, configuration: windowBackground, outputScale: outputScale)
            }
            if let preset { image = try ScreenshotBackgroundService.applyPreset(to: image, settings: preset) }
            if options.addBorder { image = try ScreenshotPixelProcessor.addingBorder(to: image) }
            if options.convertToSRGB || options.scaleToOneX || options.addBorder || cursor != nil || preset != nil
                || (windowBackground != nil && windowBackground?.mode != .original) {
                try ScreenshotPixelProcessor.writePNG(image, to: url, scale: outputScale)
            }
            return ScreenshotPixelProcessingResult(width: image.width, height: image.height, sourceScale: scale, outputScale: outputScale)
        }
    }
}

nonisolated enum ScreenshotOutputError: LocalizedError {
    case cursorBoundsMissing

    var errorDescription: String? {
        "Cursor compositing requires the screenshot bounds in Quartz coordinates."
    }
}
