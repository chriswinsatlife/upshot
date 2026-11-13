import AppKit
import ImageIO
import SwiftUI

struct AnnotationColorPreview: ViewModifier {
    let model: AnnotationEditorModel

    private struct PreviewKey: Equatable {
        let url: URL?
        let adjustments: AnnotationColorAdjustments
    }

    func body(content: Content) -> some View {
        content.task(id: PreviewKey(url: model.baseImageURL, adjustments: model.backgroundSettings.colorAdjustments)) {
            await model.updateColorPreview()
        }
    }
}

extension AnnotationEditorModel {
    func updateColorPreview() async {
        guard let url = baseImageURL else { return }
        let settings = backgroundSettings.colorAdjustments
        let longestEdge = max(imageSize.width, imageSize.height)
        let maximumSize = UpshotPreferences.lowResolutionEditorPreview ? min(longestEdge, previewImageMaxPixelSize) : longestEdge
        do {
            try await Task.sleep(for: .milliseconds(50))
            let output = try await Task.detached(priority: .userInitiated) {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceCreateThumbnailWithTransform: true,
                        kCGImageSourceThumbnailMaxPixelSize: maximumSize,
                        kCGImageSourceShouldCache: false
                      ] as CFDictionary) else { throw CocoaError(.fileReadCorruptFile) }
                return try AnnotationColorProcessor.render(image, settings: settings)
            }.value
            guard !Task.isCancelled, baseImageURL == url, backgroundSettings.colorAdjustments == settings else { return }
            previewImage = NSImage(cgImage: output, size: CGSize(width: output.width, height: output.height))
            previewCGImage = output
            isPreviewDownscaled = CGFloat(output.width) < imageSize.width || CGFloat(output.height) < imageSize.height
            NSLog("Annotation color preview applied exposure=%.2f contrast=%.2f saturation=%.2f temperature=%.1f",
                  settings.exposure, settings.contrast, settings.saturation, settings.temperature)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = "Color adjustment failed: \(error.localizedDescription)"
        }
    }
}
