import AppKit
import Foundation

@MainActor
enum PointerArtworkCapture {
    static func defaultArtwork() -> PointerArtwork? {
        capture(NSCursor.arrow, id: "pointer-default")
    }

    static func capture(_ cursor: NSCursor, id: String) -> PointerArtwork? {
        let image = cursor.image
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .png, properties: [:]),
              !imageData.isEmpty else {
            return nil
        }

        let imageSize = image.size
        let width = imageSize.width.isFinite && imageSize.width > 0
            ? imageSize.width
            : CGFloat(bitmap.pixelsWide)
        let height = imageSize.height.isFinite && imageSize.height > 0
            ? imageSize.height
            : CGFloat(bitmap.pixelsHigh)
        guard width > 0, height > 0 else { return nil }

        let hotSpot = cursor.hotSpot
        return PointerArtwork(
            artworkID: id,
            imageData: imageData,
            anchorPoint: PointerArtwork.Point(
                x: min(max(hotSpot.x.isFinite ? hotSpot.x : 0, 0), width),
                y: min(max(hotSpot.y.isFinite ? hotSpot.y : 0, 0), height)
            ),
            referenceSize: PointerArtwork.Size(
                width: width,
                height: height
            )
        )
    }
}

extension PointerArtwork {
    @MainActor
    func styled(_ style: RecordingCursorStyle, inverted: Bool) -> PointerArtwork {
        if style.usesArtworkCatalog {
            guard let pose = style.replacesEveryCursor ? RecordingCursorPose.arrow : SystemPointer.pose(for: self) else {
                return self
            }
            return RecordingCursorArtworkCatalog.artwork(style: style, pose: pose, inverted: inverted) ?? self
        }
        if let shape = style.shape, shape.isCircle {
            return shape.artwork ?? self
        }
        let inverts = inverted && style.shape != nil
        if imageData == SystemPointer.arrow?.imageData {
            var arrow = style.shape?.artwork(inverted: inverts) ?? self
            arrow.leans = true
            return arrow
        }
        if imageData == SystemPointer.pointingHand?.imageData || SystemPointer.isBrowserHand(self) {
            return PointerShape.hand.artwork(inverted: inverts) ?? self
        }
        return self
    }
}

@MainActor
private enum SystemPointer {
    static let arrow = PointerArtworkCapture.capture(NSCursor.arrow, id: "")
    static let pointingHand = PointerArtworkCapture.capture(NSCursor.pointingHand, id: "")

    private static let poses: [(RecordingCursorPose, PointerArtwork?)] = [
        (.arrow, arrow),
        (.pointer, pointingHand),
        (.text, PointerArtworkCapture.capture(NSCursor.iBeam, id: "")),
        (.crosshair, PointerArtworkCapture.capture(NSCursor.crosshair, id: "")),
        (.openHand, PointerArtworkCapture.capture(NSCursor.openHand, id: "")),
        (.closedHand, PointerArtworkCapture.capture(NSCursor.closedHand, id: "")),
        (.resizeEW, PointerArtworkCapture.capture(NSCursor.columnResize, id: "")),
        (.resizeNS, PointerArtworkCapture.capture(NSCursor.rowResize, id: "")),
        (.notAllowed, PointerArtworkCapture.capture(NSCursor.operationNotAllowed, id: "")),
        (.resizeEW, PointerArtworkCapture.capture(NSCursor.resizeLeftRight, id: "")),
        (.resizeNS, PointerArtworkCapture.capture(NSCursor.resizeUpDown, id: ""))
    ]

    static func pose(for artwork: PointerArtwork) -> RecordingCursorPose? {
        if let pose = poses.first(where: { $0.1?.imageData == artwork.imageData })?.0 {
            return pose
        }
        return isBrowserHand(artwork) ? .pointer : nil
    }

    static func isBrowserHand(_ artwork: PointerArtwork) -> Bool {
        artwork.referenceSize == PointerArtwork.Size(width: 32, height: 32)
            && artwork.anchorPoint == PointerArtwork.Point(x: 13, y: 8)
    }
}
