
import SwiftUI
import CoreGraphics
import ImageIO
import ScreenCaptureKit

@Observable
final class ScreenshotManager {

    static let shared = ScreenshotManager()

    private init() {}

    private(set) var lastAreaCaptureDisplayID: CGDirectDisplayID?
    private(set) var lastAreaCaptureSource: CaptureSource?
    private(set) var lastCaptureMetadata = ScreenshotCaptureMetadata(captureType: .area)


    func captureFullscreen(displayID: CGDirectDisplayID?) async -> URL? {
        let metadata = ScreenshotCaptureMetadata(captureType: .fullscreen)
        let displayIndex = Self.screencaptureDisplayIndex(for: displayID)
        guard let url = await runScreencapture(args: ["-D", "\(displayIndex)"] + ScreenshotCursorService.noninteractiveCaptureArguments) else { return nil }

        lastCaptureMetadata = metadata
        trimEmptyMenuBarIfNeeded(at: url, displayID: displayID)
        return url
    }

    private static func screencaptureDisplayIndex(for displayID: CGDirectDisplayID?) -> Int {
        guard let displayID else { return 1 }

        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return 1 }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return 1 }

        if let index = displays.firstIndex(of: displayID) {
            return index + 1
        }
        return 1
    }


    func captureWindow(includeShadow: Bool = false, delaySeconds: Int = 0) async -> URL? {
        do {
            guard let selection = try await AreaCaptureSelection.shared.select(initialMode: .window, delaySeconds: delaySeconds,
                                                                              includeWindowShadow: includeShadow) else { return nil }
            return try await capture(selection, includeShadow: includeShadow, delaySeconds: delaySeconds)
        } catch {
            AppLog.event("capture", "window_capture_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }


    func captureArea(includeShadow: Bool = false, delaySeconds: Int = 0, smartElement: Bool = false) async -> URL? {
        do {
            guard let selection = try await AreaCaptureSelection.shared.select(smartElement: smartElement, delaySeconds: delaySeconds,
                                                                              includeWindowShadow: includeShadow) else { return nil }
            return try await capture(selection, includeShadow: includeShadow, delaySeconds: delaySeconds)
        } catch {
            AppLog.event("capture", "area_capture_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    func capture(_ selection: AreaCaptureSelectionResult, includeShadow: Bool, delaySeconds: Int) async throws -> URL? {
        defer { DesktopIconVisibilityService.shared.endCapture(selection.desktopIconLease) }
        lastAreaCaptureDisplayID = nil
        lastAreaCaptureSource = nil
        lastAreaCaptureDisplayID = selection.snapshots.max {
            let left = $0.frame.intersection(selection.rect)
            let right = $1.frame.intersection(selection.rect)
            return (left.isNull ? 0 : left.width * left.height) < (right.isNull ? 0 : right.width * right.height)
        }?.displayID
        lastAreaCaptureSource = selection.source
        switch selection.kind {
        case .scrolling, .recording:
            throw CocoaError(.featureUnsupported)
        case .area, .element, .window, .fullscreen: break
        }
        guard let image = try await image(for: selection, delaySeconds: delaySeconds) else { return nil }
        let scale = selection.composedImageScale ?? selection.snapshots.filter { $0.frame.intersects(selection.rect) }.map(\.scale).max() ?? 1
        let topLeft = ActiveDisplayResolver.quartzPoint(fromAppKit: CGPoint(x: selection.rect.minX, y: selection.rect.maxY))
        let bounds = CGRect(origin: topLeft, size: selection.rect.size)
        let delayedCursor: ScreenshotCursorSnapshot?
        if case .window = selection.kind { delayedCursor = nil }
        else { delayedCursor = delaySeconds > 0 ? ScreenshotCursorService.snapshot() : selection.cursor }
        let captureType: ScreenshotOutputCaptureType
        switch selection.kind {
        case .window: captureType = .window
        case .fullscreen: captureType = .fullscreen
        default: captureType = .area
        }
        lastCaptureMetadata = ScreenshotCaptureMetadata(captureType: captureType, bounds: bounds, sourceScale: scale,
                                                        cursor: delayedCursor, skipBackgroundPreset: delaySeconds > 0 ? NSEvent.modifierFlags.contains(.shift) : selection.skipBackgroundPreset,
                                                        capturedAt: delaySeconds > 0 ? Date() : selection.capturedAt)
        let outputImage: CGImage
        if case .fullscreen(let displayID) = selection.kind {
            outputImage = NotchBarTrimmer.trimmingEmptyMenuBar(image, displayID: displayID)
        } else {
            outputImage = image
        }
        let url = try writeAreaImage(outputImage, scale: scale)
        switch selection.kind {
        case .area, .element: AreaSelectionMemory.rememberScreenshot(rect: selection.rect)
        default: break
        }
        return url
    }

    func capturePreviousArea(delaySeconds: Int = 0) async -> URL? {
        guard let rect = AreaSelectionMemory.previousScreenshotRect else {
            AppLog.event("capture", "previous_screenshot_area_unavailable", fields: ["reason": "missing_selection_or_changed_display_layout"])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "No previous screenshot area", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
        do {
            let snapshots = try await AreaCaptureSnapshot.captureAll()
            let selection = AreaCaptureSelectionResult(kind: .area, rect: rect, snapshots: snapshots, frozen: true, source: AreaCaptureSelection.captureSource(in: rect), cursor: ScreenshotCursorService.snapshot(), skipBackgroundPreset: NSEvent.modifierFlags.contains(.shift))
            AppLog.event("capture", "previous_screenshot_area_capture_started")
            return try await capture(selection, includeShadow: false, delaySeconds: delaySeconds)
        } catch {
            AppLog.event("capture", "previous_screenshot_area_capture_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    func image(for selection: AreaCaptureSelectionResult, delaySeconds: Int) async throws -> CGImage? {
        defer { DesktopIconVisibilityService.shared.endCapture(selection.desktopIconLease) }
        guard !Task.isCancelled else { return nil }
        if delaySeconds == 0, let image = selection.composedImage { return image }
        guard await prepareCapture(selection, delaySeconds: delaySeconds) else { return nil }
        if case .window(let windowID) = selection.kind {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
            guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw CocoaError(.fileReadUnknown) }
            let snapshot = try await AreaCaptureWindowSnapshot.capture(window: window, includeShadow: selection.windowIncludesShadow,
                                                                      showsCursor: selection.windowShowsCursor, eventTime: selection.selectionTime)
            if let eventTime = selection.selectionTime {
                snapshot.logTiming(windowID: windowID, shadow: selection.windowIncludesShadow, eventTime: eventTime, acquisition: "window-countdown")
            }
            return snapshot.image
        }
        let snapshots: [AreaCaptureSnapshot]
        if delaySeconds == 0 {
            snapshots = selection.snapshots
        } else {
            snapshots = try await AreaCaptureSnapshot.captureAll(desktopIconsPrepared: selection.desktopIconLease != nil)
        }
        let image = try AreaCaptureSnapshot.composite(snapshots, in: selection.rect)
        selection.logTiming(composedAt: ProcessInfo.processInfo.systemUptime, acquisition: delaySeconds > 0 ? "countdown" : "frozen", frames: snapshots)
        return image
    }

    private func prepareCapture(_ selection: AreaCaptureSelectionResult, delaySeconds: Int) async -> Bool {
        let displayID = selection.snapshots.first { $0.frame.contains(CGPoint(x: selection.rect.midX, y: selection.rect.midY)) }?.displayID
            ?? selection.snapshots.first { $0.frame.intersects(selection.rect) }?.displayID
        guard await CaptureCountdownPresenter.shared.runIfNeeded(seconds: delaySeconds, displayID: displayID) else { return false }
        return !Task.isCancelled
    }

    private func writeAreaImage(_ image: CGImage, scale: CGFloat) throws -> URL {
        let url = URL(fileURLWithPath: generateTempPath(extension: "png"))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        AppLog.event("capture", "area_capture_saved", fields: ["file": url.lastPathComponent, "height": String(describing: image.height), "width": String(describing: image.width)])
        return url
    }


    private func runScreencapture(args: [String], desktopIconsPrepared: Bool = false) async -> URL? {
        let lease: UUID?
        do {
            lease = desktopIconsPrepared ? nil : try await DesktopIconVisibilityService.shared.beginCapture()
        } catch {
            AppLog.event("capture", "screenshot_acquisition_failed", fields: ["error": AppLog.error(error)])
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
        defer { DesktopIconVisibilityService.shared.endCapture(lease) }
        let filePath = generateTempPath(extension: "png")

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                process.arguments = args + ["-x", "-t", "png", filePath]

                do {
                    try process.run()
                    process.waitUntilExit()
                    AppLog.event("capture", "native_screenshot_finished", fields: ["file": URL(fileURLWithPath: filePath).lastPathComponent, "status": String(describing: process.terminationStatus)])

                    if process.terminationStatus == 0,
                       FileManager.default.fileExists(atPath: filePath) {
                        continuation.resume(returning: URL(fileURLWithPath: filePath))
                    } else {
                        continuation.resume(returning: nil)
                    }
                } catch {
                    print("screencapture failed: \(error)")
                    continuation.resume(returning: nil)
                }
            }
        }
    }


    private func trimEmptyMenuBarIfNeeded(at url: URL, displayID: CGDirectDisplayID?) {
        guard let displayID,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            return
        }

        let trimmed = NotchBarTrimmer.trimmingEmptyMenuBar(image, displayID: displayID)
        guard trimmed !== image else { return }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1,
            nil
        ) else {
            return
        }

        CGImageDestinationAddImage(destination, trimmed, properties)
        CGImageDestinationFinalize(destination)
    }


    private func generateTempPath(extension ext: String) -> String {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let initialURL = directory.appendingPathComponent(ScreenshotFileNaming.fileName(extension: ext))
        guard FileManager.default.fileExists(atPath: initialURL.path) else {
            return initialURL.path
        }

        let baseName = initialURL.deletingPathExtension().lastPathComponent
        for index in 1...10_000 {
            let candidateURL = directory
                .appendingPathComponent("\(baseName)-\(index)")
                .appendingPathExtension(ext)
            if !FileManager.default.fileExists(atPath: candidateURL.path) {
                return candidateURL.path
            }
        }

        return directory
            .appendingPathComponent("Upshot_\(UUID().uuidString)")
            .appendingPathExtension(ext)
            .path
    }
}
