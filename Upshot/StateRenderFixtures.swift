import AppKit
import AVFoundation
import ImageIO
import UniformTypeIdentifiers

struct StateRenderFixtures {
    let screenshots: [URL]
    let image: NSImage
    var pixelSize: CGSize {
        guard let image = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return image.size }
        return CGSize(width: image.width, height: image.height)
    }
    let project: RecordingSession
    let items: [CaptureLibraryItem]

    static func make() async throws -> Self {
        guard let root = UpshotStorage.fixtureRoot else { throw StateRenderFailure(message: "Fixture storage is unavailable") }
        try FileManager.default.createDirectory(at: UpshotStorage.applicationSupportDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: UpshotStorage.configurationFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("[preferences]\nplaySounds = false\n".utf8).write(to: UpshotStorage.configurationFileURL)
        resetPreferences()
        var screenshots: [URL] = []
        for (index, title) in ["Release Overview", "Capture Workflow", "Design Review", "Project Notes"].enumerated() {
            let image = makeImage(title: title, variant: index)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw StateRenderFailure(message: "Fixture image generation failed") }
            let url = root.appendingPathComponent(title + ".png")
            let bitmap = NSBitmapImageRep(cgImage: cg)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw StateRenderFailure(message: "Fixture PNG encoding failed") }
            try png.write(to: url)
            screenshots.append(ScreenshotHistoryStore.shared.importScreenshot(from: url, source: CaptureSource(bundleIdentifier: nil, appName: "Upshot", windowTitle: title)))
        }
        guard let firstScreenshot = screenshots.first, let image = NSImage(contentsOf: firstScreenshot) else {
            throw StateRenderFailure(message: "Fixture screenshot could not be loaded")
        }
        let gif = root.appendingPathComponent("Capture Animation.gif")
        guard let destination = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 1, nil),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw StateRenderFailure(message: "Fixture GIF generation failed") }
        CGImageDestinationAddImage(destination, cg, nil)
        guard CGImageDestinationFinalize(destination) else { throw StateRenderFailure(message: "Fixture GIF writing failed") }
        _ = ScreenshotHistoryStore.shared.importScreenshot(from: gif)
        let project = try RecordingSessionStore.createSession()
        try await makeVideo(image: image, to: project.screenURL)
        try await makeVideo(image: makeCameraImage(), to: project.cameraURL)
        try makeAudio(to: project.directoryURL.appendingPathComponent("narration.wav"))
        var manifest = CaptureManifest()
        manifest.pixelWidth = 1280
        manifest.pixelHeight = 800
        manifest.duration = 8
        manifest.pointerSynthesized = true
        manifest.pixelScale = 2
        try project.writeCaptureManifest(manifest)
        var pointer = PointerCaptureFile()
        pointer.travel = (0...8).map { PointerTravelSample(time: Double($0), x: 0.35 + Double($0) * 0.03, y: 0.45) }
        pointer.keystrokes = [RecordingKeystrokeEvent(time: 2, modifiers: ["⌘"], key: "C")]
        try project.writePointerCapture(pointer)
        project.writeProjectMetadata(RecordingProjectMetadata(displayName: "Capture Walkthrough", savedAt: Date(timeIntervalSince1970: 1_794_441_600)))
        try FileManager.default.copyItem(at: screenshots[0], to: project.directoryURL.appendingPathComponent("overlay.png"))
        _ = await ScreenshotHistoryStore.shared.importRecordingSession(project)
        _ = await ScreenshotHistoryStore.shared.importVideo(from: project.screenURL)
        let items = await CaptureHistoryActions.recentCaptures()
        AppLog.event("rendering", "state_renderer_fixtures", fields: ["captures": String(describing: items.count), "outcome": "created", "recordingDuration": "8", "screenshots": String(describing: screenshots.count)])
        return Self(screenshots: screenshots, image: image, project: project, items: items)
    }

    func windowAreaImage() throws -> NSImage {
        let area = CGRect(x: 88.0 / 1280, y: 78.0 / 800, width: 1030.4 / 1280, height: 644.0 / 800)
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let cropped = source.cropping(to: CGRect(x: area.minX * CGFloat(source.width), y: area.minY * CGFloat(source.height),
                                                       width: area.width * CGFloat(source.width), height: area.height * CGFloat(source.height)).integral) else {
            throw StateRenderFailure(message: "The fixture window area image could not be cropped")
        }
        return NSImage(cgImage: cropped, size: CGSize(width: image.size.width * area.width, height: image.size.height * area.height))
    }

    static func resetPreferences() {
        let defaults = UpshotStorage.defaults
        defaults.removePersistentDomain(forName: UpshotStorage.fixtureIdentifier)
        defaults.register(defaults: [
            UpshotPreferences.exportDirectoryPathKey: UpshotStorage.applicationSupportDirectory.appendingPathComponent("Exports").path,
            UpshotPreferences.playSoundsKey: false,
            UpshotPreferences.libraryAnalyzeCapturesKey: false,
            UpshotPreferences.previewAutoCloseSecondsKey: 0,
            "captureLibrary.inspectorVisible": true,
            "StudioInspectorFoldedSections": "",
            "annotationInspector.expandedAdvancedSections": ["camera"]
        ])
    }

    func annotationModel(tool: AnnotationTool, annotated: Bool = true) -> AnnotationEditorModel {
        let model = AnnotationEditorModel()
        model.sourceURL = screenshots[0]
        model.baseImageURL = screenshots[0]
        model.previewImage = image
        model.previewCGImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        model.imageSize = image.size
        model.selectedTool = tool
        model.engine.tool = tool
        if annotated { model.installRenderAnnotations() }
        return model
    }

    func studioModel() async throws -> RecordingStudioModel {
        if FileManager.default.fileExists(atPath: project.draftDocumentURL.path) {
            try FileManager.default.removeItem(at: project.draftDocumentURL)
        }
        let model = RecordingStudioModel(url: project.directoryURL)
        model.isAgentSession = true
        await model.load()
        guard model.isLoaded else { throw StateRenderFailure(message: model.loadError ?? "Fixture recording failed to load") }
        model.installRenderOverlays()
        model.seek(to: 0.4)
        return model
    }

    private static func makeImage(title: String, variant: Int) -> NSImage {
        let size = CGSize(width: 1280, height: 800)
        return NSImage(size: size, flipped: false) { rect in
            NSColor(calibratedRed: 0.08 + Double(variant) * 0.02, green: 0.13, blue: 0.22, alpha: 1).setFill()
            rect.fill()
            let panel = CGRect(x: 80, y: 70, width: 1120, height: 660)
            NSColor(calibratedWhite: 0.97, alpha: 1).setFill()
            NSBezierPath(roundedRect: panel, xRadius: 22, yRadius: 22).fill()
            NSColor(calibratedWhite: 0.91, alpha: 1).setFill()
            CGRect(x: 80, y: 660, width: 1120, height: 1).fill()
            for (index, color) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                color.setFill()
                NSBezierPath(ovalIn: CGRect(x: 108 + index * 25, y: 688, width: 13, height: 13)).fill()
            }
            let dark = NSColor(calibratedRed: 0.12, green: 0.17, blue: 0.25, alpha: 1)
            ("UPSHOT / WORKSPACE" as NSString).draw(at: CGPoint(x: 220, y: 683), withAttributes: [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: dark])
            (title as NSString).draw(at: CGPoint(x: 130, y: 555), withAttributes: [.font: NSFont.systemFont(ofSize: 42, weight: .bold), .foregroundColor: dark])
            ("Capture, annotate, and share a clear view of the work." as NSString).draw(at: CGPoint(x: 132, y: 515), withAttributes: [.font: NSFont.systemFont(ofSize: 20), .foregroundColor: NSColor.darkGray])
            for index in 0..<3 {
                let card = CGRect(x: 130 + index * 350, y: 265, width: 320, height: 200)
                NSColor(calibratedRed: 0.88 - Double(index) * 0.09, green: 0.93 - Double(index) * 0.04, blue: 0.98, alpha: 1).setFill()
                NSBezierPath(roundedRect: card, xRadius: 14, yRadius: 14).fill()
                (["Screenshots", "Recordings", "Review"][index] as NSString).draw(at: CGPoint(x: card.minX + 22, y: card.maxY - 50), withAttributes: [.font: NSFont.systemFont(ofSize: 23, weight: .semibold), .foregroundColor: dark])
                for line in 0..<3 {
                    NSColor(calibratedWhite: 0.45, alpha: 0.18).setFill()
                    NSBezierPath(roundedRect: CGRect(x: card.minX + 22, y: card.minY + 36 + CGFloat(line * 25), width: CGFloat(180 + line * 25), height: 10), xRadius: 5, yRadius: 5).fill()
                }
            }
            ("Ready for review" as NSString).draw(at: CGPoint(x: 132, y: 185), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .medium), .foregroundColor: dark])
            ("Every capture keeps its context." as NSString).draw(at: CGPoint(x: 132, y: 145), withAttributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray])
            return true
        }
    }

    private static func makeCameraImage() -> NSImage {
        NSImage(size: CGSize(width: 1280, height: 800), flipped: false) { rect in
            NSColor(calibratedRed: 0.25, green: 0.31, blue: 0.4, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedRed: 0.28, green: 0.56, blue: 0.75, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: 330, y: -200, width: 620, height: 650)).fill()
            NSColor(calibratedRed: 0.85, green: 0.66, blue: 0.5, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: 470, y: 320, width: 340, height: 360)).fill()
            NSColor(calibratedWhite: 0.13, alpha: 1).setFill()
            NSBezierPath(ovalIn: CGRect(x: 460, y: 570, width: 360, height: 140)).fill()
            return true
        }
    }

    private static func makeAudio(to url: URL) throws {
        let samples = 16000 * 8
        var data = Data("RIFF".utf8)
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        append(UInt32(36 + samples * 2))
        data.append(Data("WAVEfmt ".utf8))
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1)); append(UInt32(16000)); append(UInt32(32000)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(samples * 2))
        for index in 0..<samples { append(Int16(sin(Double(index) * 2 * .pi * 220 / 16000) * 900)) }
        try data.write(to: url)
    }

    private static func makeVideo(image: NSImage, to url: URL) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 1280, AVVideoHeightKey: 800])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 1280, kCVPixelBufferHeightKey as String: 800])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? StateRenderFailure(message: "Fixture video writer failed") }
        writer.startSession(atSourceTime: .zero)
        guard let pool = adaptor.pixelBufferPool,
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw StateRenderFailure(message: "Fixture video buffer pool failed") }
        for frame in 0..<32 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(5)) }
            var buffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else { throw StateRenderFailure(message: "Fixture video buffer allocation failed") }
            CVPixelBufferLockBaseAddress(buffer, [])
            guard let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 1280, height: 800,
                                          bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { throw StateRenderFailure(message: "Fixture video drawing failed") }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: 1280, height: 800))
            CVPixelBufferUnlockBaseAddress(buffer, [])
            guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 4)) else { throw writer.error ?? StateRenderFailure(message: "Fixture video append failed") }
        }
        writer.endSession(atSourceTime: CMTime(value: 8, timescale: 1))
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? StateRenderFailure(message: "Fixture video completion failed") }
    }
}
