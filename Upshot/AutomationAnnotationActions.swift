import AppKit

enum AutomationAnnotationActions {
    static let actions: Set<CaptureHotkeyAction> = [
        .editorHighlighter, .editorMeasure, .editorTextPlain, .editorTextLabel, .editorTextCallout,
        .editorRedactionStyle, .editorWatermark, .editorColorAdjustments,
        .editorRotateClockwise, .editorRotateCounterclockwise, .editorFlipHorizontal, .editorFlipVertical,
        .editorCombineSideBySide, .editorCombineStacked, .editorDrawingSmoothing,
        .editorObjectShadows, .editorExpandCanvas, .editorAlwaysOnTop
    ]

    static func perform(_ action: CaptureHotkeyAction, parameters: [String: String]) async throws {
        let model = try AutomationEditorActions.activeModel()
        guard model.sourceURL != nil else { throw AutomationError.message("The screenshot editor has no image loaded.") }
        let operation = try operation(action, parameters: parameters, model: model)
        if let operation { await AnnotationEditorAction.perform(operation, on: model) }
        if let error = model.errorMessage { throw AutomationError.message(error) }
    }

    static func operation(_ action: CaptureHotkeyAction, parameters: [String: String], model: AnnotationEditorModel) throws -> AnnotationEditorAction? {
        let value = parameters["value"]
        switch action {
        case .editorHighlighter: return .selectTool(.highlighter)
        case .editorMeasure: return .selectTool(.measure)
        case .editorTextPlain, .editorTextLabel, .editorTextCallout:
            let style: AnnotationTextStyle = action == .editorTextPlain ? .plain : action == .editorTextLabel ? .label : .callout
            if !model.isTextStyleAvailable { model.selectTool(.text) }
            return .setTextStyle(style)
        case .editorRedactionStyle:
            let styles = RedactionKind.allCases
            let next = styles[(styles.firstIndex(of: model.redactionKind) ?? 0) + 1 < styles.count
                ? (styles.firstIndex(of: model.redactionKind) ?? 0) + 1 : 0]
            guard let style = value.flatMap(RedactionKind.init(rawValue:)) ?? (value == nil ? next : nil) else {
                throw AutomationError.message("Redaction style must be one of: \(styles.map(\.rawValue).joined(separator: ", ")).")
            }
            return .setRedactionStyle(style)
        case .editorRotateClockwise: return .transformImage(.rotateClockwise)
        case .editorRotateCounterclockwise: return .transformImage(.rotateCounterclockwise)
        case .editorFlipHorizontal: return .transformImage(.flipHorizontal)
        case .editorFlipVertical: return .transformImage(.flipVertical)
        case .editorCombineSideBySide, .editorCombineStacked:
            let layout: AnnotationImageCombination = action == .editorCombineSideBySide ? .sideBySide : .stacked
            guard let path = parameters["path"] else {
                model.chooseImageToCombine(layout)
                return nil
            }
            let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
            guard FileManager.default.fileExists(atPath: url.path) else { throw AutomationError.message("The image to combine does not exist.") }
            return .combineImage(url, layout)
        case .editorDrawingSmoothing:
            let smoothing = try number(value, default: model.drawingSmoothing > 0 ? 0 : 0.62, range: 0...1)
            return .setDrawingSmoothing(smoothing)
        case .editorObjectShadows:
            return .setObjectShadows(try boolean(value, default: !model.objectShadowsEnabled))
        case .editorExpandCanvas:
            return .setAutomaticallyExpandsCanvas(try boolean(value, default: !model.automaticallyExpandsCanvas))
        case .editorAlwaysOnTop:
            return .setAlwaysOnTop(try boolean(value, default: !UpshotPreferences.annotationEditorAlwaysOnTop))
        case .editorColorAdjustments:
            let settings = try value.map { try JSONDecoder().decode(AnnotationColorAdjustments.self, from: Data($0.utf8)) }
                ?? AnnotationColorAdjustments()
            guard settings.exposure.isFinite, (-3...3).contains(settings.exposure),
                  settings.contrast.isFinite, (0...2).contains(settings.contrast),
                  settings.saturation.isFinite, (0...2).contains(settings.saturation),
                  settings.temperature.isFinite, (-100...100).contains(settings.temperature) else {
                throw AutomationError.message("Color adjustments require exposure -3...3, contrast 0...2, saturation 0...2, and temperature -100...100.")
            }
            return .setColorAdjustments(settings)
        case .editorWatermark:
            var settings = model.backgroundSettings.watermark
            if let value {
                let patch = try JSONDecoder().decode(WatermarkParameters.self, from: Data(value.utf8))
                if let text = patch.text { settings.text = text; settings.imageData = nil }
                if let opacity = patch.opacity { settings.opacity = CGFloat(try number(String(opacity), default: 0.18, range: 0...1)) }
                if let position = patch.position { settings.position = position }
                if let rotation = patch.rotationDegrees { settings.rotationDegrees = CGFloat(try number(String(rotation), default: 0, range: -360...360)) }
                if let size = patch.fontSize { settings.fontSize = CGFloat(try number(String(size), default: 72, range: 1...1000)) }
                if let width = patch.imageWidth { settings.imageWidth = CGFloat(try number(String(width), default: 0.2, range: 0.02...0.9)) }
                settings.isEnabled = patch.isEnabled ?? true
            } else {
                settings.isEnabled.toggle()
            }
            if let path = parameters["path"] {
                let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                let data = try Data(contentsOf: url)
                guard NSImage(data: data) != nil else { throw AutomationError.message("The watermark image could not be read.") }
                settings.imageData = data
                settings.isEnabled = true
            }
            return .setWatermark(settings)
        default: throw AutomationError.message("Unsupported screenshot editor action.")
        }
    }

    private static func boolean(_ value: String?, default fallback: Bool) throws -> Bool {
        guard let value else { return fallback }
        guard let result = Bool(value) else { throw AutomationError.message("The value must be true or false.") }
        return result
    }

    private static func number(_ value: String?, default fallback: Double, range: ClosedRange<Double>) throws -> Double {
        guard let value else { return fallback }
        guard let result = Double(value), result.isFinite, range.contains(result) else {
            throw AutomationError.message("The value must be a finite number in \(range.lowerBound)...\(range.upperBound).")
        }
        return result
    }

    private struct WatermarkParameters: Decodable {
        var text: String?
        var opacity: Double?
        var position: AnnotationWatermarkPosition?
        var rotationDegrees: Double?
        var fontSize: Double?
        var imageWidth: Double?
        var isEnabled: Bool?
    }
}
