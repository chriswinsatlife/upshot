
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AnnotationEditorModel {
    @ObservationIgnored let engine = AnnoEditor()
    private(set) var revision = 0

    var sourceURL: URL?
    var baseImageURL: URL?
    var previewImage: NSImage?
    @ObservationIgnored var previewCGImage: CGImage?
    var isPreviewDownscaled = false
    var imageSize: CGSize = .zero

    var selectedTool: AnnotationTool = .rectangle
    var selectedSwatch: AnnotationSwatch = .red
    var strokeWidth: CGFloat = 4
    var redactionDensity: CGFloat = 0.55
    var backgroundSettings = AnnotationBackgroundSettings()
    var appliedBackgroundPresetID: AnnotationBackgroundPreset.ID?
    var previewBackground: AnnotationBackgroundStyle?
    var isProcessingImage = false
    var errorMessage: String?
    var isSmartRedacting = false
    var smartRedactionMessage: String?

    var isCropping = false
    var cropPixelRect: CGRect = .zero
    var cropDrag: CropDrag?
    var cropAspect: CropAspectRatio = .freeform

    var canvasViewport = AnnotationCanvasViewport()
    var canvasRevealID = 0
    static let cropHandleMargin: CGFloat = 26

    var textFontFamily: AnnoFontFamily = .pro
    var textFontSize: CGFloat = 48
    var textIsBold = true
    var textIsItalic = false
    var textIsUnderline = false
    var textAlignment: NSTextAlignment = .left

    struct CropSnapshot {
        var baseImageURL: URL?
        var imageSize: CGSize
        var shapes: [AnnoShape]
        var bindings: [ArrowBinding]
    }

    var cropUndoStack: [CropSnapshot] = []
    var cropRedoStack: [CropSnapshot] = []
    var ownedCropURLs: Set<URL> = []

    let previewImageMaxPixelSize: CGFloat = 2880
    @ObservationIgnored private var wallpaperCacheLease: BoundedCGImageCache.Lease?
    @ObservationIgnored private var smartRedactionTask: Task<Void, Never>?
    private var smartRedactionGeneration = UUID()

    init() {
        engine.onChange = { [weak self] in
            self?.revision &+= 1
            self?.updateCanvasExpansion()
        }
    }


    var shapes: [AnnoShape] { engine.shapes }
    var bindings: [ArrowBinding] { engine.document.bindings }
    var hasAnnotations: Bool { !engine.shapes.isEmpty }
    var selectionCount: Int { engine.selectedIds.count }
    var editingTextID: AnnoShapeID? { engine.editingTextId }

    var isTransformingExistingAnnotation: Bool {
        switch engine.interaction {
        case .translating, .resizing, .rotating, .draggingArrowHandle: true
        default: false
        }
    }

    private var selectedShape: AnnoShape? {
        engine.selectedIds.count == 1 ? engine.selectedShapes.first : nil
    }

    var inspectedTool: AnnotationTool? {
        selectedShape?.tool
            ?? engine.selectedShapes.first?.tool
            ?? (selectedTool.createsAnnotation ? selectedTool : nil)
    }

    var isColorStyleAvailable: Bool { isStyleAvailable { $0.supportsColorStyle } }
    var isStrokeStyleAvailable: Bool { isStyleAvailable { $0.supportsStrokeStyle } }
    var isRedactionStyleAvailable: Bool { isStyleAvailable { $0.supportsRedactionDensityStyle } }

    var hasInspectorStyleControls: Bool {
        isTextStyleAvailable || isColorStyleAvailable || isStrokeStyleAvailable || isRedactionStyleAvailable
    }

    private func isStyleAvailable(_ supportsStyle: (AnnotationTool) -> Bool) -> Bool {
        let selected = engine.selectedShapes
        if selected.isEmpty {
            return inspectedTool.map(supportsStyle) ?? false
        }
        return selected.contains { supportsStyle($0.tool) }
    }


    func load(url: URL?, dismiss: DismissAction) {
        cancelSmartRedaction()
        guard let url else {
            dismiss()
            return
        }

        wallpaperCacheLease = AnnotationBackgroundRenderer.beginWallpaperUse()
        removeOwnedCropFiles()
        applyAnnotationPreset()
        resetZoom()
        sourceURL = url

        let document = ScreenshotHistoryStore.shared.loadEditDocument(for: url)
        let candidateBaseURL = ScreenshotHistoryStore.baseImageURL(for: url)
        let renderSourceURL: URL
        if let document, document.version >= 2,
           FileManager.default.fileExists(atPath: candidateBaseURL.path) {
            renderSourceURL = candidateBaseURL
            backgroundSettings = document.backgroundSettings
            appliedBackgroundPresetID = nil
        } else {
            renderSourceURL = url
            let presetStore = AnnotationBackgroundPresetStore.shared
            let activePreset = ScreenshotOutputMetadata.hasAppliedBackgroundPreset(at: url) ? nil : presetStore.activePreset
            backgroundSettings = document?.backgroundSettings ?? activePreset?.settings ?? AnnotationBackgroundSettings()
            appliedBackgroundPresetID = document == nil ? activePreset?.id : nil
        }

        baseImageURL = renderSourceURL
        imageSize = ScreenshotImageLoader.imageSize(at: renderSourceURL) ?? .zero
        previewImage = makePreviewImage(from: renderSourceURL)
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)

        engine.viewport = AnnoViewport(imageFrame: .zero, imageSize: imageSize)
        engine.replaceDocument(
            shapes: document?.shapes ?? [],
            bindings: document?.bindings ?? []
        )
        engine.tool = selectedTool

        isCropping = false
        cropPixelRect = .zero
        cropDrag = nil
        cropAspect = .freeform
        cropUndoStack = []
        cropRedoStack = []
        RedactionImageProcessor.removeAllCachedPreviewImages()
        errorMessage = nil
        smartRedactionMessage = nil

        if previewImage == nil || imageSize == .zero {
            errorMessage = "Unable to load screenshot."
        }

        markSaved()
    }

    func makePreviewImage(from url: URL) -> NSImage? {
        if UpshotPreferences.lowResolutionEditorPreview {
            isPreviewDownscaled = max(imageSize.width, imageSize.height) > previewImageMaxPixelSize
            return ScreenshotImageLoader.downsampledImage(at: url, maxPixelSize: previewImageMaxPixelSize)
        } else {
            isPreviewDownscaled = false
            return ScreenshotImageLoader.fullResolutionImage(at: url)
        }
    }

    func releaseEditorResources() {
        cancelSmartRedaction()
        wallpaperCacheLease = nil
        savedSnapshot = nil
        sourceURL = nil
        baseImageURL = nil
        previewImage = nil
        previewCGImage = nil
        imageSize = .zero
        isPreviewDownscaled = false
        isCropping = false
        cropUndoStack.removeAll()
        cropRedoStack.removeAll()
        engine.replaceDocument(shapes: [])
        removeOwnedCropFiles()
        RedactionImageProcessor.removeAllCachedPreviewImages()
    }

    private(set) var isCommitting = false

    @discardableResult
    func commitEdits() async throws -> URL? {
        guard !isCommitting else { throw CocoaError(.userCancelled) }
        guard let sourceURL = self.sourceURL else { return nil }
        isCommitting = true
        defer { isCommitting = false }
        var committedSnapshot = currentSnapshot()

        let baseURL = self.baseImageURL ?? sourceURL
        let shapes = self.shapes
        let bindings = self.bindings
        let backgroundSettings = self.backgroundSettings
        let hasContent = !shapes.isEmpty || backgroundSettings.hasRenderableContent || self.isCropped
        let hadDocument = ScreenshotHistoryStore.shared.hasEditDocument(for: sourceURL)

        guard hasContent || hadDocument else {
            self.markSaved()
            return nil
        }

        let resultURL: URL
        if hasContent {
            let annotatedURL = try await AnnotationRenderer.renderToTemporaryFileInBackground(
                sourceURL: baseURL,
                shapes: shapes,
                backgroundSettings: backgroundSettings
            )
            let document = AnnotationDocument(
                shapes: shapes,
                bindings: bindings,
                background: backgroundSettings
            )
            resultURL = try ScreenshotHistoryStore.shared.commitAnnotations(
                displayURL: sourceURL,
                baseURL: baseURL,
                renderedURL: annotatedURL,
                document: document
            )
            self.baseImageURL = ScreenshotHistoryStore.baseImageURL(for: resultURL)
        } else {
            resultURL = try ScreenshotHistoryStore.shared.removeAnnotations(displayURL: sourceURL)
            self.baseImageURL = resultURL
        }

        committedSnapshot.baseImageURL = self.baseImageURL
        savedSnapshot = committedSnapshot
        return resultURL
    }


    private struct EditSnapshot: Equatable {
        var baseImageURL: URL?
        var shapes: [AnnoShape]
        var bindings: [ArrowBinding]
        var background: StoredBackground
    }

    private var savedSnapshot: EditSnapshot?

    private func currentSnapshot() -> EditSnapshot {
        EditSnapshot(
            baseImageURL: baseImageURL,
            shapes: shapes,
            bindings: bindings,
            background: StoredBackground(backgroundSettings)
        )
    }

    var hasUnsavedChanges: Bool {
        _ = revision
        guard sourceURL != nil, let savedSnapshot else { return false }
        return currentSnapshot() != savedSnapshot
    }

    func markSaved() {
        savedSnapshot = currentSnapshot()
    }


    func updateViewport(imageFrame: CGRect) {
        engine.viewport = AnnoViewport(imageFrame: imageFrame, imageSize: imageSize)
    }

    private func updatePageLimits(boundaryFrame: CGRect) {
        guard !UpshotPreferences.annotationAutomaticallyExpandCanvas, !boundaryFrame.isEmpty else {
            engine.pageLimits = nil
            return
        }
        let topLeft = engine.screenToPage(Vec(boundaryFrame.origin))
        let bottomRight = engine.screenToPage(Vec(CGPoint(x: boundaryFrame.maxX, y: boundaryFrame.maxY)))
        engine.pageLimits = Box(topLeft.x, topLeft.y, bottomRight.x - topLeft.x, bottomRight.y - topLeft.y)
    }

    private func pointer(at location: CGPoint) -> PointerInfo {
        let flags = NSEvent.modifierFlags
        let screenPoint = Vec(location)
        return PointerInfo(
            screenPoint: screenPoint,
            pagePoint: engine.screenToPage(screenPoint),
            shift: flags.contains(.shift),
            alt: flags.contains(.option),
            command: flags.contains(.command)
        )
    }

    func beginInteraction(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !isCropping else { return }
        updateViewport(imageFrame: imageFrame)
        updatePageLimits(boundaryFrame: boundaryFrame)
        if !UpshotPreferences.annotationAutomaticallyExpandCanvas, engine.tool != .select, !boundaryFrame.contains(location) {
            engine.stopEditingText()
            selectedTool = engine.tool
            return
        }
        engine.pointerDown(pointer(at: location))
        selectedTool = engine.tool
        syncStyleFromSelection()
    }

    func updateInteraction(to location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !isCropping else { return }
        updateViewport(imageFrame: imageFrame)
        engine.pointerMove(pointer(at: drawingLocation(location, in: boundaryFrame)))
        selectedTool = engine.tool
    }

    func endInteraction(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) {
        guard !isCropping else { return }
        updateViewport(imageFrame: imageFrame)
        engine.pointerUp(pointer(at: drawingLocation(location, in: boundaryFrame)))
        selectedTool = engine.tool
        syncStyleFromSelection()
    }

    private func drawingLocation(_ location: CGPoint, in boundaryFrame: CGRect) -> CGPoint {
        guard !UpshotPreferences.annotationAutomaticallyExpandCanvas, engine.tool != .select, !boundaryFrame.isEmpty else { return location }
        return CGPoint(
            x: min(max(location.x, boundaryFrame.minX), boundaryFrame.maxX),
            y: min(max(location.y, boundaryFrame.minY), boundaryFrame.maxY)
        )
    }

    func hoveredAnnotation(at location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) -> AnnoShape? {
        guard UpshotPreferences.annotationAutomaticallyExpandCanvas || boundaryFrame.contains(location) else { return nil }
        updateViewport(imageFrame: imageFrame)
        return engine.hitShape(at: engine.screenToPage(Vec(location)))
    }

    func hoveredHandle(at location: CGPoint, imageFrame: CGRect) -> AnnoSelectionHandle? {
        updateViewport(imageFrame: imageFrame)
        return engine.handle(at: Vec(location))
    }

    func containsInteractionPoint(_ location: CGPoint, imageFrame: CGRect, boundaryFrame: CGRect) -> Bool {
        UpshotPreferences.annotationAutomaticallyExpandCanvas || boundaryFrame.contains(location)
    }


    func selectTool(_ tool: AnnotationTool) {
        selectedTool = tool
        engine.tool = tool
        saveAnnotationPreset()
    }

    func setSwatch(_ swatch: AnnotationSwatch) {
        selectedSwatch = swatch
        engine.currentSwatch = swatch
        saveAnnotationPreset()

        engine.applyStyleToSelection { shape in
            switch shape.kind {
            case var .geo(p): p.swatch = swatch; shape.kind = .geo(p)
            case var .draw(p): p.swatch = swatch; shape.kind = .draw(p)
            case var .arrow(p): p.swatch = swatch; shape.kind = .arrow(p)
            case var .text(p): p.swatch = swatch; shape.kind = .text(p)
            case var .numbered(p): p.swatch = swatch; shape.kind = .numbered(p)
            case .redaction, .highlight: break
            }
        }
    }

    func setStrokeWidth(_ width: CGFloat) {
        strokeWidth = width
        engine.currentStrokeWidth = Double(width)
        saveAnnotationPreset()

        let pageWidth = engine.pageStrokeWidth(Double(width))
        engine.applyStyleToSelection { shape in
            switch shape.kind {
            case var .geo(p): p.strokeWidth = pageWidth; shape.kind = .geo(p)
            case var .draw(p): p.strokeWidth = pageWidth; shape.kind = .draw(p)
            case var .arrow(p): p.strokeWidth = pageWidth; shape.kind = .arrow(p)
            default: break
            }
        }
    }

    func setRedactionDensity(_ density: CGFloat) {
        redactionDensity = density
        engine.currentRedactionDensity = Double(density)
        saveAnnotationPreset()

        engine.applyStyleToSelection { shape in
            if case var .redaction(p) = shape.kind {
                p.density = Double(density)
                shape.kind = .redaction(p)
            }
        }
    }

    private func syncStyleFromSelection() {
        guard let shape = selectedShape else { return }
        if let swatch = shape.swatch, shape.tool.supportsColorStyle {
            selectedSwatch = swatch
            engine.currentSwatch = swatch
        }
        if shape.tool.supportsStrokeStyle, shape.strokeWidth > 0 {
            strokeWidth = CGFloat(engine.sliderStrokeWidth(shape.strokeWidth))
            engine.currentStrokeWidth = Double(strokeWidth)
        }
        if let props = shape.redactionProps {
            redactionDensity = CGFloat(props.density)
            engine.currentRedactionDensity = props.density
        }
        if let props = shape.textProps {
            textFontFamily = props.fontFamily
            textFontSize = CGFloat(props.fontSize)
            textIsBold = props.isBold
            textIsItalic = props.isItalic
            textIsUnderline = props.isUnderline
            textAlignment = props.align.nsTextAlignment
        }
    }


    func deleteSelectedAnnotation() {
        engine.deleteSelected()
    }

    func selectAllAnnotations() {
        selectedTool = .select
        engine.selectAll()
    }

    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        engine.nudgeSelected(dx: Double(dx), dy: Double(dy))
    }

    func commitTextEditing() {
        engine.stopEditingText()
    }

    func setText(_ text: String, for id: AnnoShapeID) {
        engine.updateEditingText(id, to: text)
    }

    func undo() {
        guard !isCropping else { return }
        if engine.canUndo {
            engine.undo()
            return
        }
        undoCrop()
    }

    func redo() {
        guard !isCropping else { return }
        if engine.canRedo {
            engine.redo()
            return
        }
        redoCrop()
    }


    func smartRedact(using tool: AnnotationTool) {
        guard tool.isRedactionTool,
              !isSmartRedacting,
              let recognitionURL = baseImageURL ?? sourceURL else {
            return
        }

        let loadedSourceURL = sourceURL
        isSmartRedacting = true
        smartRedactionMessage = nil

        let generation = UUID()
        smartRedactionGeneration = generation
        smartRedactionTask = Task { @MainActor [weak self] in
            let regions: [SmartRedactionRegion]
            do {
                regions = try await SmartRedactionRecognizer.recognizeSensitiveRegions(at: recognitionURL)
            } catch {
                guard let self, self.smartRedactionGeneration == generation else { return }
                self.smartRedactionTask = nil
                self.isSmartRedacting = false
                guard !(error is CancellationError), !Task.isCancelled,
                      self.sourceURL == loadedSourceURL,
                      self.baseImageURL == recognitionURL || self.sourceURL == recognitionURL else { return }
                self.smartRedactionMessage = ImageTextRecognizer.failureTitle(for: error)
                NSLog("Smart Redaction %@: %@", ImageTextRecognizer.failureTitle(for: error), String(describing: error))
                return
            }

            guard !Task.isCancelled, let self, self.smartRedactionGeneration == generation else { return }
            self.smartRedactionTask = nil
            self.isSmartRedacting = false
            guard self.sourceURL == loadedSourceURL,
                  self.baseImageURL == recognitionURL || self.sourceURL == recognitionURL else { return }

            self.applySmartRedactionRegions(regions, tool: tool)
        }
    }

    private func cancelSmartRedaction() {
        smartRedactionGeneration = UUID()
        smartRedactionTask?.cancel()
        smartRedactionTask = nil
        isSmartRedacting = false
    }

    private func applySmartRedactionRegions(_ regions: [SmartRedactionRegion], tool: AnnotationTool) {
        let renderable = regions.compactMap { region -> AnnoShape? in
            let rect = CGRect(
                x: region.bounds.minX * imageSize.width,
                y: region.bounds.minY * imageSize.height,
                width: region.bounds.width * imageSize.width,
                height: region.bounds.height * imageSize.height
            )
            guard rect.width >= 2, rect.height >= 2 else { return nil }
            var props = RedactionProps()
            props.kind = tool == .blur ? .blur : .pixelate
            props.density = Double(redactionDensity)
            props.w = Double(rect.width)
            props.h = Double(rect.height)
            return AnnoShape(x: Double(rect.minX), y: Double(rect.minY), kind: .redaction(props))
        }

        guard !renderable.isEmpty else {
            smartRedactionMessage = "No sensitive text found."
            return
        }

        engine.markUndo()
        for shape in renderable { engine.document.add(shape) }
        engine.selectedIds = Set(renderable.map(\.id))
        selectedTool = tool
        engine.tool = tool
        engine.notifyChanged()
        smartRedactionMessage = "Added \(renderable.count) redaction\(renderable.count == 1 ? "" : "s")."
    }


    func annotationBounds(for imageFrame: CGRect, boundaryFrame: CGRect) -> CGRect {
        guard imageFrame.width > 0, imageFrame.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        return CGRect(
            x: (boundaryFrame.minX - imageFrame.minX) / imageFrame.width,
            y: (boundaryFrame.minY - imageFrame.minY) / imageFrame.height,
            width: boundaryFrame.width / imageFrame.width,
            height: boundaryFrame.height / imageFrame.height
        )
    }


    private static func startingTool(lastUsed: AnnotationTool) -> AnnotationTool {
        let choice = UserDefaults.standard.string(forKey: UpshotPreferences.annotationStartingToolKey)
            ?? AnnotationTool.select.rawValue
        if choice == UpshotPreferences.startingToolLastUsed { return lastUsed }
        return AnnotationTool(rawValue: choice) ?? .select
    }

    private func applyAnnotationPreset() {
        let preset = AnnotationPresetStore.load()
        selectedTool = Self.startingTool(lastUsed: preset.selectedTool)
        selectedSwatch = preset.swatch
        strokeWidth = CGFloat(preset.strokeWidth)
        redactionDensity = CGFloat(preset.redactionDensity)
        textFontFamily = AnnoFontFamily(rawValue: preset.textFontName) ?? .pro
        textFontSize = CGFloat(preset.textFontSize)
        textIsBold = preset.textIsBold
        textIsItalic = preset.textIsItalic
        textIsUnderline = preset.textIsUnderline
        textAlignment = preset.textAlignment

        engine.tool = selectedTool
        engine.currentSwatch = selectedSwatch
        engine.currentStrokeWidth = Double(strokeWidth)
        engine.currentRedactionDensity = Double(redactionDensity)
        engine.currentFontFamily = textFontFamily
        engine.currentTextFontSize = Double(textFontSize)
        engine.currentTextIsBold = textIsBold
        engine.currentTextIsItalic = textIsItalic
        engine.currentTextIsUnderline = textIsUnderline
        engine.currentTextAlign = TextAlign(textAlignment)
    }

    func saveAnnotationPreset() {
        let customSwatch = AnnotationSwatch.allCases.contains(selectedSwatch) ? nil : CodableSwatch(swatch: selectedSwatch)
        let preset = AnnotationStylePreset(
            selectedToolRawValue: selectedTool.rawValue,
            swatchID: selectedSwatch.id,
            customSwatch: customSwatch,
            strokeWidth: Double(strokeWidth),
            redactionDensity: Double(redactionDensity),
            textFontName: textFontFamily.rawValue,
            textFontSize: Double(textFontSize),
            textIsBold: textIsBold,
            textIsItalic: textIsItalic,
            textIsUnderline: textIsUnderline,
            textAlignmentRawValue: textAlignment.rawValue
        )
        AnnotationPresetStore.save(preset)
    }

    func applyBackgroundPreset(_ preset: AnnotationBackgroundPreset) {
        backgroundSettings = preset.settings
        appliedBackgroundPresetID = preset.id
    }
}


extension AnnotationEditorModel {
    var isCropped: Bool { !cropUndoStack.isEmpty }

    func applyCrop() {
        guard isCropping else { return }

        let crop = imageSize.width > 0 && imageSize.height > 0
            ? CGRect(
                x: cropPixelRect.minX / imageSize.width,
                y: cropPixelRect.minY / imageSize.height,
                width: cropPixelRect.width / imageSize.width,
                height: cropPixelRect.height / imageSize.height
            ).intersection(CropGeometry.unit)
            : .zero
        let shownImageFrame = displayedImageFrame
        var revealFrom = shownImageFrame
        defer {
            isCropping = false
            cropDrag = nil
            cropPixelRect = cropBounds
            cropAspect = .freeform
            revealCanvasLeavingCrop(imageAt: revealFrom)
        }

        guard !crop.isEmpty, crop != CropGeometry.unit else { return }

        guard let baseURL = baseImageURL,
              let result = AnnotationImageCropper.crop(url: baseURL, normalizedRect: crop) else {
            errorMessage = "Unable to crop the image."
            return
        }

        guard let snapshot = currentCropSnapshot() else {
            try? FileManager.default.removeItem(at: result.url)
            errorMessage = "Unable to preserve the image for crop undo."
            return
        }

        let oldImageSize = imageSize
        let usedCrop = result.normalizedRect
        let newImageSize = result.pixelSize

        let offsetX = Double(usedCrop.minX * oldImageSize.width)
        let offsetY = Double(usedCrop.minY * oldImageSize.height)
        let scaleX = usedCrop.width > 0 ? Double(newImageSize.width) / Double(usedCrop.width * oldImageSize.width) : 1
        let scaleY = usedCrop.height > 0 ? Double(newImageSize.height) / Double(usedCrop.height * oldImageSize.height) : 1
        let uniform = (scaleX + scaleY) / 2

        let moved = engine.shapes.map { shape -> AnnoShape in
            var shape = shape
            shape.x = (shape.x - offsetX) * scaleX
            shape.y = (shape.y - offsetY) * scaleY
            scaleShapeContents(&shape, sx: scaleX, sy: scaleY, uniform: uniform)
            return shape
        }

        baseImageURL = result.url
        ownedCropURLs.insert(result.url)
        imageSize = newImageSize
        previewImage = makePreviewImage(from: result.url)
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        engine.viewport = AnnoViewport(imageFrame: engine.viewport.imageFrame, imageSize: imageSize)
        engine.replaceDocument(shapes: moved, bindings: engine.document.bindings)

        cropUndoStack.append(snapshot)
        cropRedoStack.removeAll()

        revealFrom = shownImageFrame.map { frame in
            CGRect(x: frame.minX + usedCrop.minX * frame.width,
                   y: frame.minY + usedCrop.minY * frame.height,
                   width: usedCrop.width * frame.width,
                   height: usedCrop.height * frame.height)
        }
        errorMessage = nil
    }

    private func scaleShapeContents(_ shape: inout AnnoShape, sx: Double, sy: Double, uniform: Double) {
        switch shape.kind {
        case var .geo(p):
            p.w *= sx; p.h *= sy
            p.strokeWidth *= uniform
            p.cornerRadius *= uniform
            shape.kind = .geo(p)
        case var .redaction(p):
            p.w *= sx; p.h *= sy
            shape.kind = .redaction(p)
        case var .highlight(p):
            p.w *= sx; p.h *= sy
            shape.kind = .highlight(p)
        case var .numbered(p):
            p.diameter *= uniform
            shape.kind = .numbered(p)
        case var .draw(p):
            p.points = p.points.map { Vec($0.x * sx, $0.y * sy, $0.z) }
            p.strokeWidth *= uniform
            shape.kind = .draw(p)
        case var .arrow(p):
            p.start = Vec(p.start.x * sx, p.start.y * sy)
            p.end = Vec(p.end.x * sx, p.end.y * sy)
            p.bend *= uniform
            p.strokeWidth *= uniform
            shape.kind = .arrow(p)
        case var .text(p):
            p.fontSize *= uniform
            p.w *= sx
            shape.kind = .text(p)
        }
    }

    private func undoCrop() {
        guard let previous = cropUndoStack.last else { return }
        guard let current = currentCropSnapshot() else {
            errorMessage = "Unable to preserve the image for crop redo."
            return
        }
        cropUndoStack.removeLast()
        cropRedoStack.append(current)
        restore(previous)
    }

    private func redoCrop() {
        guard let next = cropRedoStack.last else { return }
        guard let current = currentCropSnapshot() else {
            errorMessage = "Unable to preserve the image for crop undo."
            return
        }
        cropRedoStack.removeLast()
        cropUndoStack.append(current)
        restore(next)
    }

    func currentCropSnapshot() -> CropSnapshot? {
        let stableBaseURL: URL?
        if let baseImageURL {
            guard let snapshotURL = stableCropSnapshotURL(for: baseImageURL) else { return nil }
            stableBaseURL = snapshotURL
        } else {
            stableBaseURL = nil
        }

        return CropSnapshot(
            baseImageURL: stableBaseURL,
            imageSize: imageSize,
            shapes: engine.shapes,
            bindings: engine.document.bindings
        )
    }

    private func stableCropSnapshotURL(for url: URL) -> URL? {
        if ownedCropURLs.contains(url) { return url }

        let fileExtension = url.pathExtension.isEmpty ? "png" : url.pathExtension
        let destinationURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("Upshot_CropSnapshot_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension(fileExtension)

        do {
            try FileManager.default.copyItem(at: url, to: destinationURL)
            ownedCropURLs.insert(destinationURL)
            return destinationURL
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            return nil
        }
    }

    private func restore(_ snapshot: CropSnapshot) {
        baseImageURL = snapshot.baseImageURL
        imageSize = snapshot.imageSize
        previewImage = snapshot.baseImageURL.flatMap(makePreviewImage(from:))
        previewCGImage = previewImage?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        engine.viewport = AnnoViewport(imageFrame: engine.viewport.imageFrame, imageSize: imageSize)
        engine.replaceDocument(shapes: snapshot.shapes, bindings: snapshot.bindings)
        resetZoom()
    }

    private func removeOwnedCropFiles() {
        for url in ownedCropURLs {
            try? FileManager.default.removeItem(at: url)
        }
        ownedCropURLs.removeAll()
    }

}


extension AnnotationEditorModel {
    func previewBackground(_ background: AnnotationBackgroundStyle, isHovering: Bool) {
        if isHovering {
            previewBackground = background
        } else if previewBackground == background {
            previewBackground = nil
        }
    }

    var displayedBackgroundStyle: AnnotationBackgroundStyle {
        guard let previewBackground, previewBackground != .none,
              backgroundSettings.style != .none
        else { return backgroundSettings.style }
        return previewBackground
    }
}
