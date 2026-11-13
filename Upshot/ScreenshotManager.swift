
import SwiftUI
import CoreGraphics
import ImageIO

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
        if UpshotPreferences.screenshotShowCursor {
            do {
                guard let selection = try await AreaCaptureSelection.shared.select(initialMode: .window) else { return nil }
                return try await capture(selection, includeShadow: includeShadow, delaySeconds: delaySeconds)
            } catch {
                NSLog("Window capture failed: %@", error.localizedDescription)
                CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
                return nil
            }
        }
        let probe = CaptureSourceProbe(tracksPointer: true)
        NSLog("Window capture started: shadow=%d delay=%ld", includeShadow, delaySeconds)
        var args = ["-w"]
        if !includeShadow {
            args.append("-o")
        }
        args.append(contentsOf: delayArguments(delaySeconds))
        let url = await runScreencapture(args: args)
        lastAreaCaptureSource = probe.finish(.window)
        let windowFrame = probe.selectedWindowBounds.map(ActiveDisplayResolver.appKitRect(fromQuartz:))
        let targetScreen = windowFrame.flatMap { frame in
            NSScreen.screens.filter { $0.frame.intersects(frame) }.max {
                let left = $0.frame.intersection(frame)
                let right = $1.frame.intersection(frame)
                return left.width * left.height < right.width * right.height
            }
        }
        lastAreaCaptureDisplayID = targetScreen.flatMap(ActiveDisplayResolver.displayID(for:))
            ?? ActiveDisplayResolver.activeDisplayID(preferPointer: true)
        lastCaptureMetadata = ScreenshotCaptureMetadata(captureType: .window,
            skipBackgroundPreset: delaySeconds > 0 ? NSEvent.modifierFlags.contains(.shift) : probe.selectionModifiers.contains(.shift))
        return url
    }


    func captureArea(includeShadow: Bool = false, delaySeconds: Int = 0, smartElement: Bool = false) async -> URL? {
        do {
            guard let selection = try await AreaCaptureSelection.shared.select(smartElement: smartElement) else { return nil }
            return try await capture(selection, includeShadow: includeShadow, delaySeconds: delaySeconds)
        } catch {
            NSLog("Area capture failed: %@", String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    func capture(_ selection: AreaCaptureSelectionResult, includeShadow: Bool, delaySeconds: Int) async throws -> URL? {
        lastAreaCaptureDisplayID = nil
        lastAreaCaptureSource = nil
        lastAreaCaptureDisplayID = selection.snapshots.max {
            let left = $0.frame.intersection(selection.rect)
            let right = $1.frame.intersection(selection.rect)
            return (left.isNull ? 0 : left.width * left.height) < (right.isNull ? 0 : right.width * right.height)
        }?.displayID
        lastAreaCaptureSource = selection.source
        switch selection.kind {
        case .fullscreen(let displayID):
            guard await prepareCapture(selection, delaySeconds: delaySeconds) else { return nil }
            let url = await captureFullscreen(displayID: displayID)
            if delaySeconds == 0 {
                lastCaptureMetadata.skipBackgroundPreset = selection.skipBackgroundPreset
                lastCaptureMetadata.capturedAt = selection.capturedAt
            }
            return url
        case .scrolling, .recording:
            throw CocoaError(.featureUnsupported)
        case .area, .element, .window: break
        }
        if case .window(let windowID) = selection.kind {
            guard await prepareCapture(selection, delaySeconds: delaySeconds) else { return nil }
            var arguments = ["-l", "\(windowID)"]
            if !includeShadow { arguments.append("-o") }
            NSLog("Area window capture started: window=%u shadow=%d", windowID, includeShadow)
            let metadata = ScreenshotCaptureMetadata(captureType: .window,
                skipBackgroundPreset: delaySeconds > 0 ? NSEvent.modifierFlags.contains(.shift) : selection.skipBackgroundPreset,
                capturedAt: delaySeconds > 0 ? Date() : selection.capturedAt)
            let url = await runScreencapture(args: arguments + ScreenshotCursorService.noninteractiveCaptureArguments)
            lastCaptureMetadata = metadata
            return url
        }
        guard let image = try await image(for: selection, delaySeconds: delaySeconds) else { return nil }
        let scale = selection.snapshots.filter { $0.frame.intersects(selection.rect) }.map(\.scale).max() ?? 1
        let topLeft = ActiveDisplayResolver.quartzPoint(fromAppKit: CGPoint(x: selection.rect.minX, y: selection.rect.maxY))
        let bounds = CGRect(origin: topLeft, size: selection.rect.size)
        let delayedCursor = delaySeconds > 0 ? ScreenshotCursorService.snapshot() : selection.cursor
        lastCaptureMetadata = ScreenshotCaptureMetadata(captureType: .area, bounds: bounds, sourceScale: scale,
                                                        cursor: delayedCursor, skipBackgroundPreset: delaySeconds > 0 ? NSEvent.modifierFlags.contains(.shift) : selection.skipBackgroundPreset,
                                                        capturedAt: delaySeconds > 0 ? Date() : selection.capturedAt)
        let url = try writeAreaImage(image, scale: scale)
        AreaSelectionMemory.rememberScreenshot(rect: selection.rect)
        return url
    }

    func capturePreviousArea(delaySeconds: Int = 0) async -> URL? {
        guard let rect = AreaSelectionMemory.previousScreenshotRect else {
            NSLog("Previous screenshot area unavailable: missing selection or changed display layout")
            CaptureTextFeedbackPresenter.shared.showFailure(title: "No previous screenshot area", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
        do {
            let snapshots = try await AreaCaptureSnapshot.captureAll()
            let selection = AreaCaptureSelectionResult(kind: .area, rect: rect, snapshots: snapshots, frozen: true, source: AreaCaptureSelection.captureSource(in: rect), cursor: ScreenshotCursorService.snapshot(), skipBackgroundPreset: NSEvent.modifierFlags.contains(.shift))
            NSLog("Previous screenshot area capture started")
            return try await capture(selection, includeShadow: false, delaySeconds: delaySeconds)
        } catch {
            NSLog("Previous screenshot area capture failed: %@", String(describing: error))
            CaptureTextFeedbackPresenter.shared.showFailure(title: "Capture failed", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
            return nil
        }
    }

    func image(for selection: AreaCaptureSelectionResult, delaySeconds: Int) async throws -> CGImage? {
        guard await prepareCapture(selection, delaySeconds: delaySeconds) else { return nil }
        let snapshots: [AreaCaptureSnapshot]
        if selection.frozen && delaySeconds == 0 {
            snapshots = selection.snapshots
        } else {
            snapshots = try await AreaCaptureSnapshot.captureAll()
        }
        return try AreaCaptureSnapshot.composite(snapshots, in: selection.rect)
    }

    private func prepareCapture(_ selection: AreaCaptureSelectionResult, delaySeconds: Int) async -> Bool {
        let displayID = selection.snapshots.first { $0.frame.contains(CGPoint(x: selection.rect.midX, y: selection.rect.midY)) }?.displayID
            ?? selection.snapshots.first { $0.frame.intersects(selection.rect) }?.displayID
        guard await CaptureCountdownPresenter.shared.runIfNeeded(seconds: delaySeconds, displayID: displayID) else { return false }
        do {
            try await Task.sleep(for: .milliseconds(120))
            try Task.checkCancellation()
            return true
        } catch { return false }
    }

    private func writeAreaImage(_ image: CGImage, scale: CGFloat) throws -> URL {
        let url = URL(fileURLWithPath: generateTempPath(extension: "png"))
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, [kCGImagePropertyDPIWidth: 72 * scale, kCGImagePropertyDPIHeight: 72 * scale] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        NSLog("Area capture saved: pixels=%ldx%ld file=%@", image.width, image.height, url.lastPathComponent)
        return url
    }

    private func delayArguments(_ seconds: Int) -> [String] {
        seconds > 0 ? ["-T", "\(seconds)"] : []
    }


    private func runScreencapture(args: [String]) async -> URL? {
        let lease: UUID?
        do {
            lease = try await DesktopIconVisibilityService.shared.beginCapture()
        } catch {
            NSLog("Screenshot acquisition failed: %@", error.localizedDescription)
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
                    NSLog("Native screenshot finished: status=%d file=%@", process.terminationStatus, URL(fileURLWithPath: filePath).lastPathComponent)

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
