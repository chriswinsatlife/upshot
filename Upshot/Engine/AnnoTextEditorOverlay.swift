import AppKit
import Foundation

@MainActor
final class AnnoTextEditorOverlay: NSTextView {
    private weak var editor: AnnoEditor?
    private var shapeId: AnnoShapeID?

    var editedShapeId: AnnoShapeID? { shapeId }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    convenience init(editor: AnnoEditor, shapeId: AnnoShapeID) {
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        layoutManager.addTextContainer(container)

        self.init(frame: .zero, textContainer: container)
        self.editor = editor
        self.shapeId = shapeId
    }

    private func configure() {
        isRichText = false
        importsGraphics = false
        drawsBackground = false
        isVerticallyResizable = true
        isHorizontallyResizable = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = false
        allowsUndo = false
        focusRingType = .none
        delegate = self
    }

    func sync() {
        guard let editor, let shapeId,
              let shape = editor.document.shape(shapeId),
              let props = shape.textProps else { return }

        let zoom = editor.viewport.scale
        var viewProps = props
        viewProps.fontSize = Swift.max(1, props.fontSize * zoom)
        viewProps.w = props.w * zoom

        let fontSize = CGFloat(viewProps.fontSize)
        let font = TextMeasure.font(viewProps, opticalSize: props.fontSize)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = props.align.nsTextAlignment
        paragraph.minimumLineHeight = TextMeasure.lineHeight(viewProps)
        paragraph.maximumLineHeight = TextMeasure.lineHeight(viewProps)
        paragraph.lineBreakMode = .byWordWrapping

        var attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: (AnnotationTextDecoration.padding(props) > 0 ? props.swatch.numberedCircleTextNSColor : props.swatch.nsColor),
        ]
        if props.isUnderline {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }

        typingAttributes = attributes
        defaultParagraphStyle = paragraph
        self.font = font
        textColor = (AnnotationTextDecoration.padding(props) > 0 ? props.swatch.numberedCircleTextNSColor : props.swatch.nsColor)
        alignment = paragraph.alignment
        insertionPointColor = (AnnotationTextDecoration.padding(props) > 0 ? props.swatch.numberedCircleTextNSColor : props.swatch.nsColor)
        if let storage = textStorage, storage.length > 0 {
            storage.setAttributes(attributes, range: NSRange(location: 0, length: storage.length))
        }

        let textSize = TextMeasure.measure(props)
        let inset = AnnotationTextDecoration.padding(props)
        let origin = editor.pageToScreen(shape.pageTransform.applyToPoint(Vec(inset, inset)))
        var width = Swift.max(Double(textSize.width) * zoom, Double(fontSize) * 0.6)
        var height = Swift.max(Double(textSize.height) * zoom, Double(TextMeasure.lineHeight(viewProps)))

        if props.autoSize, let container = textContainer, let layoutManager {
            container.size = CGSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
            layoutManager.ensureLayout(for: container)
            let used = layoutManager.usedRect(for: container)
            let natural = ceil(used.width)
            container.size = CGSize(width: natural + 2, height: CGFloat.greatestFiniteMagnitude)
            width = Swift.max(width, Double(natural + fontSize * 0.5))
            height = Swift.max(height, Double(ceil(used.height)))
        } else {
            textContainer?.size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }

        frameRotation = 0
        frame = CGRect(x: origin.x, y: origin.y, width: width, height: height)
        frameRotation = shape.rotation * 180 / .pi
    }

    func loadText() {
        guard let editor, let shapeId,
              let props = editor.document.shape(shapeId)?.textProps else { return }
        string = props.text
        sync()
        setSelectedRange(NSRange(location: (string as NSString).length, length: 0))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.cgContext.setShouldSmoothFonts(false)
        super.draw(dirtyRect)
    }

    override func cancelOperation(_ sender: Any?) {
        editor?.stopEditingText()
    }
}

extension AnnoTextEditorOverlay: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        guard let shapeId else { return }
        editor?.updateEditingText(shapeId, to: string)
        sync()
    }
}
