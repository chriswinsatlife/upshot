import AppKit
import SwiftUI

struct AnnoCanvasLayer: NSViewRepresentable {
    let editor: AnnoEditor
    let sourceImage: CGImage?
    let imageFrame: CGRect
    let imageSize: CGSize
    let spotlightClip: CGPath?
    let revision: Int

    func makeNSView(context: Context) -> AnnoCanvasNSView {
        let view = AnnoCanvasNSView()
        view.configure(
            editor: editor,
            sourceImage: sourceImage,
            imageFrame: imageFrame,
            imageSize: imageSize,
            spotlightClip: spotlightClip
        )
        return view
    }

    func updateNSView(_ view: AnnoCanvasNSView, context: Context) {
        view.configure(
            editor: editor,
            sourceImage: sourceImage,
            imageFrame: imageFrame,
            imageSize: imageSize,
            spotlightClip: spotlightClip
        )
    }

    static func dismantleNSView(_ view: AnnoCanvasNSView, coordinator: ()) {
        view.releaseResources()
    }
}

@MainActor
final class AnnoCanvasNSView: NSView {
    private var editor: AnnoEditor?
    private var sourceImage: CGImage?
    private var imageFrame: CGRect = .zero
    private var imageSize: CGSize = .zero
    private var spotlightClip: CGPath?

    private var textOverlay: AnnoTextEditorOverlay?
    private let redactionCache = AnnoRedactionPreviewCache()

    func releaseResources() {
        textOverlay?.removeFromSuperview()
        textOverlay = nil
        editor = nil
        sourceImage = nil
        spotlightClip = nil
        redactionCache.releaseResources()
        AnnoShapeDrawing.clearCaches()
    }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let textOverlay else { return nil }
        return textOverlay.frame.contains(convert(point, from: superview)) ? textOverlay : nil
    }

    func configure(
        editor: AnnoEditor,
        sourceImage: CGImage?,
        imageFrame: CGRect,
        imageSize: CGSize,
        spotlightClip: CGPath?
    ) {
        if self.editor !== editor {
            self.editor = editor
            editor.onEditingTextChanged = { [weak self] id in
                self?.updateTextOverlay(for: id)
            }
        }
        self.sourceImage = sourceImage
        redactionCache.configure(source: sourceImage, imageFrame: imageFrame)
        self.spotlightClip = spotlightClip
        self.imageFrame = imageFrame
        self.imageSize = imageSize
        editor.viewport = AnnoViewport(imageFrame: imageFrame, imageSize: imageSize)

        if textOverlay?.window != nil || editor.editingTextId != nil {
            updateTextOverlay(for: editor.editingTextId)
        }
        textOverlay?.sync()
        needsDisplay = true
    }

    private func updateTextOverlay(for id: AnnoShapeID?) {
        guard let editor else { return }
        if let id, textOverlay?.editedShapeId == id { return }

        textOverlay?.removeFromSuperview()
        textOverlay = nil
        guard let id else { return }

        let overlay = AnnoTextEditorOverlay(editor: editor, shapeId: id)
        addSubview(overlay)
        overlay.loadText()
        window?.makeFirstResponder(overlay)
        textOverlay = overlay
        needsDisplay = true
    }


    override func draw(_ dirtyRect: NSRect) {
        guard let editor,
              let context = NSGraphicsContext.current?.cgContext,
              imageSize.width > 0, imageFrame.width > 0 else { return }

        effectiveAppearance.performAsCurrentDrawingAppearance {
            render(editor: editor, in: context)
        }
    }

    private var pageToView: CGAffineTransform {
        let scale = imageFrame.width / imageSize.width
        return CGAffineTransform(translationX: imageFrame.minX, y: imageFrame.minY)
            .scaledBy(x: scale, y: scale)
    }

    private func render(editor: AnnoEditor, in context: CGContext) {
        let target = AnnoShapeDrawing.Target(
            transform: pageToView,
            pageSize: imageSize,
            sample: { [sourceImage] rect in
                guard let sourceImage, self.imageFrame.width > 0, self.imageFrame.height > 0 else { return nil }
                let sx = CGFloat(sourceImage.width) / self.imageFrame.width
                let sy = CGFloat(sourceImage.height) / self.imageFrame.height
                let requested = CGRect(
                    x: (rect.minX - self.imageFrame.minX) * sx,
                    y: (rect.minY - self.imageFrame.minY) * sy,
                    width: rect.width * sx,
                    height: rect.height * sy
                ).integral
                let crop = requested.intersection(CGRect(x: 0, y: 0, width: sourceImage.width, height: sourceImage.height))
                if crop == requested { return sourceImage.cropping(to: crop) }
                guard requested.width >= 1, requested.height >= 1,
                      let sampleContext = CGContext(data: nil, width: Int(requested.width), height: Int(requested.height),
                                                    bitsPerComponent: 8, bytesPerRow: 0,
                                                    space: sourceImage.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
                if crop.width >= 1, crop.height >= 1, let cropped = sourceImage.cropping(to: crop) {
                    sampleContext.interpolationQuality = .none
                    sampleContext.draw(cropped, in: CGRect(x: crop.minX - requested.minX, y: requested.maxY - crop.maxY,
                                                          width: crop.width, height: crop.height))
                }
                return sampleContext.makeImage()
            },
            spotlightClip: spotlightClip,
            isFlippedContext: true,
            redactionPreviewCache: redactionCache
        )

        let skipped: Set<AnnoShapeID> = editor.editingTextId.map { [$0] } ?? []
        AnnoShapeDrawing.draw(editor.document, in: context, target: target, skipping: skipped)

        if let id = editor.editingTextId, let shape = editor.document.shape(id) {
            AnnoShapeDrawing.drawShape(shape, document: editor.document, in: context, target: target, textBackgroundOnly: true)
        }
        drawOverlays(editor: editor, in: context)
    }


    private func drawOverlays(editor: AnnoEditor, in context: CGContext) {
        let accent = AnnoTheme.selectionStroke
        let lineWidth = 1.5

        if let hintedId = editor.hintedBindingId, let corners = editor.document.pageCorners(hintedId) {
            let path = CGMutablePath()
            path.addLines(between: corners.map { editor.pageToScreen($0).cgPoint })
            path.closeSubpath()
            context.addPath(path)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(lineWidth)
            context.strokePath()
            context.addPath(path)
            context.setFillColor(AnnoTheme.selectionFill.cgColor)
            context.fillPath()
        }

        if let brush = editor.brush {
            let origin = editor.pageToScreen(Vec(brush.minX, brush.minY))
            let end = editor.pageToScreen(Vec(brush.maxX, brush.maxY))
            let rect = CGRect(x: origin.x, y: origin.y, width: end.x - origin.x, height: end.y - origin.y)
            context.setFillColor(AnnoTheme.selectionFill.cgColor)
            context.fill(rect)
            context.setStrokeColor(accent.cgColor)
            context.setLineWidth(lineWidth)
            context.stroke(rect)
        }

        guard editor.editingTextId == nil, editor.tool == .select, !editor.selectedIds.isEmpty else { return }

        if editor.selectedIds.count == 1, let shape = editor.selectedShapes.first, shape.isArrow,
           let info = editor.document.arrowInfo(shape.id) {
            let transform = shape.pageTransform
            var combined = transform.cgAffineTransform.concatenating(pageToView)
            if let guidePath = ArrowPath.handles(info).solidPath().copy(using: &combined) {
                context.addPath(guidePath)
                context.setStrokeColor(accent.withAlphaComponent(0.5).cgColor)
                context.setLineWidth(1)
                context.setLineDash(phase: 0, lengths: [4, 4])
                context.strokePath()
                context.setLineDash(phase: 0, lengths: [])
            }

            for point in [info.start.handle, info.middle, info.end.handle] {
                drawRoundHandle(at: editor.pageToScreen(transform.applyToPoint(point)), in: context)
            }
            return
        }

        guard let bounds = editor.selectionBounds else { return }

        let transform = bounds.transform.cgAffineTransform.concatenating(pageToView)
        let scale = imageFrame.width / imageSize.width
        let box = bounds.box

        let framePath = CGMutablePath()
        framePath.addRect(box.cgRect, transform: transform)
        context.addPath(framePath)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()

        let handleSize = 8.0 / scale
        let cornersPath = CGMutablePath()
        for corner in box.corners {
            cornersPath.addRect(
                CGRect(
                    x: corner.x - handleSize / 2,
                    y: corner.y - handleSize / 2,
                    width: handleSize,
                    height: handleSize
                ),
                transform: transform
            )
        }
        context.addPath(cornersPath)
        context.setFillColor(AnnoTheme.handleFill.cgColor)
        context.fillPath()
        context.addPath(cornersPath)
        context.setStrokeColor(accent.cgColor)
        context.setLineWidth(lineWidth)
        context.strokePath()
    }

    private func drawRoundHandle(at point: Vec, in context: CGContext) {
        let rect = CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)
        context.setFillColor(AnnoTheme.handleFill.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(AnnoTheme.selectionStroke.cgColor)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: rect)
    }
}
