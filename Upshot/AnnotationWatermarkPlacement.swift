import AppKit
import CoreGraphics
import ImageIO

nonisolated enum AnnotationWatermarkPosition: String, CaseIterable, Codable, Identifiable {
    case tiled
    case topLeft
    case top
    case topRight
    case left
    case center
    case right
    case bottomLeft
    case bottom
    case bottomRight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .tiled: "Tiled"
        case .topLeft: "Top left"
        case .top: "Top"
        case .topRight: "Top right"
        case .left: "Left"
        case .center: "Center"
        case .right: "Right"
        case .bottomLeft: "Bottom left"
        case .bottom: "Bottom"
        case .bottomRight: "Bottom right"
        }
    }

    var anchor: CGPoint {
        switch self {
        case .tiled, .center: CGPoint(x: 0.5, y: 0.5)
        case .topLeft: CGPoint(x: 0, y: 1)
        case .top: CGPoint(x: 0.5, y: 1)
        case .topRight: CGPoint(x: 1, y: 1)
        case .left: CGPoint(x: 0, y: 0.5)
        case .right: CGPoint(x: 1, y: 0.5)
        case .bottomLeft: CGPoint(x: 0, y: 0)
        case .bottom: CGPoint(x: 0.5, y: 0)
        case .bottomRight: CGPoint(x: 1, y: 0)
        }
    }
}

nonisolated enum AnnotationWatermarkPlacement {
    static func draw(_ settings: AnnotationWatermarkSettings, in rect: CGRect, context: CGContext) {
        guard settings.isVisible, rect.width > 0, rect.height > 0 else { return }
        let image: CGImage? = settings.imageData.flatMap { data in
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
            return CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(rect.width, rect.height)
            ] as CFDictionary)
        }
        let text = NSAttributedString(string: settings.text, attributes: [
            .font: AnnotationWatermarkTypography.nsFont(size: settings.fontSize),
            .foregroundColor: settings.color.nsColor
        ])
        let naturalSize: CGSize
        if let image {
            naturalSize = CGSize(width: image.width, height: image.height)
        } else {
            guard settings.imageData == nil else { return }
            naturalSize = text.size()
        }
        guard naturalSize.width > 0, naturalSize.height > 0 else { return }
        let margin = min(rect.width, rect.height) * 0.025
        let desiredWidth = image == nil ? naturalSize.width : rect.width * min(0.9, max(0.02, settings.imageWidth))
        let scale = min(desiredWidth / naturalSize.width, max(1, rect.width - margin * 2) / naturalSize.width,
                        max(1, rect.height - margin * 2) / naturalSize.height)
        let size = CGSize(width: naturalSize.width * scale, height: naturalSize.height * scale)
        let centers: [CGPoint]
        if settings.position == .tiled {
            let rows = max(2, Int(settings.density.rounded()))
            let spacingY = rect.height / CGFloat(rows)
            let spacingX = max(size.width + margin, spacingY * 2.2)
            let columns = max(1, Int(ceil(rect.width / spacingX)))
            centers = (0..<rows).flatMap { row in
                (0..<columns).map { column in
                    CGPoint(x: rect.minX + (CGFloat(column) + 0.5) * rect.width / CGFloat(columns),
                            y: rect.minY + (CGFloat(row) + 0.5) * spacingY)
                }
            }
        } else {
            let anchor = settings.position.anchor
            centers = [CGPoint(
                x: rect.minX + margin + size.width / 2 + max(0, rect.width - margin * 2 - size.width) * anchor.x,
                y: rect.minY + margin + size.height / 2 + max(0, rect.height - margin * 2 - size.height) * anchor.y
            )]
        }
        context.saveGState()
        context.clip(to: rect)
        context.setAlpha(min(1, max(0, settings.opacity)))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        for center in centers {
            context.saveGState()
            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: -settings.rotationDegrees * .pi / 180)
            let destination = CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height)
            if let image {
                context.draw(image, in: destination)
            } else {
                context.scaleBy(x: scale, y: scale)
                text.draw(at: CGPoint(x: -naturalSize.width / 2, y: -naturalSize.height / 2))
            }
            context.restoreGState()
        }
        NSGraphicsContext.restoreGraphicsState()
        context.restoreGState()
    }
}
