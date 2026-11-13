
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import ImageIO
import UniformTypeIdentifiers

enum AnnotationRenderer {
    nonisolated(unsafe) private static let ciContext = CIContext(options: [.cacheIntermediates: false])

    static func renderInBackground(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings(),
        destinationURL: URL,
        contentType: UTType
    ) async throws {
        try await Task.detached(priority: .userInitiated) {
            try render(
                sourceURL: sourceURL,
                shapes: shapes,
                backgroundSettings: backgroundSettings,
                destinationURL: destinationURL,
                contentType: contentType
            )
        }.value
    }

    static func renderToTemporaryFileInBackground(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings()
    ) async throws -> URL {
        try await Task.detached(priority: .userInitiated) {
            try renderToTemporaryFile(
                sourceURL: sourceURL,
                shapes: shapes,
                backgroundSettings: backgroundSettings
            )
        }.value
    }

    nonisolated static func renderToTemporaryFile(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings()
    ) throws -> URL {
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Upshot_Annotated_\(UUID().uuidString.prefix(6)).png")
        try render(
            sourceURL: sourceURL,
            shapes: shapes,
            backgroundSettings: backgroundSettings,
            destinationURL: destinationURL,
            contentType: .png
        )
        return destinationURL
    }

    nonisolated static func render(
        sourceURL: URL,
        shapes: [AnnoShape],
        backgroundSettings: AnnotationBackgroundSettings = AnnotationBackgroundSettings(),
        destinationURL: URL,
        contentType: UTType
    ) throws {
        defer {
            ciContext.clearCaches()
            AnnotationMockupEffectsRenderer.clearCaches()
            AnnoShapeDrawing.clearCaches()
        }

        try autoreleasepool {
            let sourceImage = try AnnotationColorProcessor.render(
                loadSourceImage(sourceURL: sourceURL),
                settings: backgroundSettings.colorAdjustments
            )
            let colorSpace = exportColorSpace(for: sourceImage)
            let renderedImage: CGImage
            if backgroundSettings.hasRenderableContent {
                renderedImage = try AnnotationBackgroundRenderer.compose(
                    contentImage: sourceImage,
                    settings: backgroundSettings,
                    colorSpace: colorSpace,
                    foregroundOverlay: { context, layout, imageRect, imageClipPath in
                        drawAnnotations(
                            shapes,
                            in: imageRect,
                            pageSize: CGSize(width: sourceImage.width, height: sourceImage.height),
                            canvasSize: layout.canvasSize,
                            context: context,
                            colorSpace: colorSpace,
                            highlightClipPath: imageClipPath
                        )
                    },
                    canvasOverlay: { context, layout, _ in
                        AnnotationBackgroundRenderer.drawWatermark(
                            backgroundSettings.watermark,
                            in: CGRect(origin: .zero, size: layout.canvasSize),
                            context: context
                        )
                    }
                )
            } else {
                renderedImage = try renderAnnotatedImage(sourceImage, shapes: shapes, colorSpace: colorSpace)
            }

            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }

            guard let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                contentType.identifier as CFString,
                1,
                nil
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            var options: CFDictionary?
            if contentType != .png {
                options = [
                    kCGImageDestinationLossyCompressionQuality: UpshotPreferences.compressionQuality
                ] as CFDictionary
            }

            CGImageDestinationAddImage(destination, renderedImage, options)
            if !backgroundSettings.colorAdjustments.isDefault {
                let adjustments = backgroundSettings.colorAdjustments
                NSLog("Annotation color export applied exposure=%.2f contrast=%.2f saturation=%.2f temperature=%.1f",
                      adjustments.exposure, adjustments.contrast, adjustments.saturation, adjustments.temperature)
            }

            if backgroundSettings.watermark.isVisible {
                NSLog("Annotation watermark exported kind=%@ position=%@ opacity=%.2f",
                      backgroundSettings.watermark.imageData == nil ? "text" : "image",
                      backgroundSettings.watermark.position.rawValue, backgroundSettings.watermark.opacity)
            }
            guard CGImageDestinationFinalize(destination) else {
                throw CocoaError(.fileWriteUnknown)
            }
        }

    }

    nonisolated private static func loadSourceImage(sourceURL: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(
            sourceURL as CFURL,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ),
              let cgImage = CGImageSourceCreateImageAtIndex(
                source,
                0,
                [kCGImageSourceShouldCache: false] as CFDictionary
              ) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        return cgImage
    }

    nonisolated private static func exportColorSpace(for image: CGImage) -> CGColorSpace {
        guard let colorSpace = image.colorSpace,
              colorSpace.model == .rgb,
              CGContext(
                data: nil,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) != nil else {
            return CGColorSpaceCreateDeviceRGB()
        }
        return colorSpace
    }

    nonisolated private static func renderAnnotatedImage(
        _ cgImage: CGImage,
        shapes: [AnnoShape],
        colorSpace: CGColorSpace
    ) throws -> CGImage {
        let width = cgImage.width
        let height = cgImage.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }

        let fullRect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(cgImage, in: fullRect)
        drawAnnotations(
            shapes,
            in: fullRect,
            pageSize: fullRect.size,
            canvasSize: fullRect.size,
            context: context,
            colorSpace: colorSpace,
            highlightClipPath: nil
        )

        guard let renderedImage = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }

        return renderedImage
    }

    nonisolated static func drawAnnotations(
        _ shapes: [AnnoShape],
        in imageRect: CGRect,
        pageSize: CGSize,
        canvasSize: CGSize,
        context: CGContext,
        colorSpace: CGColorSpace,
        highlightClipPath: CGPath?
    ) {
        guard !shapes.isEmpty else { return }

        let document = AnnoDocument()
        document.restore(AnnoDocument.Snapshot(shapes: shapes, bindings: []))

        guard pageSize.width > 0, pageSize.height > 0 else { return }
        let scale = imageRect.width / pageSize.width

        let transform = CGAffineTransform(
            a: scale, b: 0, c: 0, d: -scale,
            tx: imageRect.minX, ty: imageRect.maxY
        )

        let target = AnnoShapeDrawing.Target(
            transform: transform,
            pageSize: pageSize,
            sample: { rect in
                guard let snapshot = context.makeImage() else { return nil }
                let flipped = CGRect(
                    x: rect.minX,
                    y: CGFloat(snapshot.height) - rect.maxY,
                    width: rect.width,
                    height: rect.height
                ).integral.intersection(
                    CGRect(x: 0, y: 0, width: snapshot.width, height: snapshot.height)
                )
                guard flipped.width >= 1, flipped.height >= 1 else { return nil }
                return snapshot.cropping(to: flipped)
            },
            spotlightClip: highlightClipPath,
            isFlippedContext: false
        )

        _ = canvasSize
        AnnoShapeDrawing.draw(document, in: context, target: target)
    }
}
