import CoreGraphics

nonisolated enum RecordingCameraCropGeometry {
    static let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
    static let minimumSize: CGFloat = 0.08

    enum Handle: String, CaseIterable, Hashable {
        case move, northwest, northeast, southwest, southeast
    }

    static func normalized(_ requested: CGRect) -> CGRect {
        guard requested.minX.isFinite, requested.minY.isFinite,
              requested.width.isFinite, requested.height.isFinite else { return unit }
        let x = min(max(requested.origin.x, 0), 1 - minimumSize)
        let y = min(max(requested.origin.y, 0), 1 - minimumSize)
        return CGRect(x: x, y: y,
                      width: min(max(requested.width, minimumSize), 1 - x),
                      height: min(max(requested.height, minimumSize), 1 - y))
    }

    static func mirrored(_ requested: CGRect) -> CGRect {
        let crop = normalized(requested)
        return CGRect(x: max(0, 1 - crop.maxX), y: crop.minY, width: crop.width, height: crop.height)
    }

    static func adjusted(_ requested: CGRect, handle: Handle, delta: CGSize) -> CGRect {
        let crop = normalized(requested)
        if handle == .move {
            return CGRect(x: min(max(crop.minX + delta.width, 0), 1 - crop.width),
                          y: min(max(crop.minY + delta.height, 0), 1 - crop.height),
                          width: crop.width, height: crop.height)
        }
        var left = crop.minX
        var right = crop.maxX
        var top = crop.minY
        var bottom = crop.maxY
        if handle == .northwest || handle == .southwest { left = min(max(left + delta.width, 0), right - minimumSize) }
        if handle == .northeast || handle == .southeast { right = min(max(right + delta.width, left + minimumSize), 1) }
        if handle == .northwest || handle == .northeast { top = min(max(top + delta.height, 0), bottom - minimumSize) }
        if handle == .southwest || handle == .southeast { bottom = min(max(bottom + delta.height, top + minimumSize), 1) }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    static func fillRect(sourceSize: CGSize, destination: CGRect, crop requested: CGRect) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return destination }
        let crop = normalized(requested)
        let scale = max(destination.width / (sourceSize.width * crop.width),
                        destination.height / (sourceSize.height * crop.height))
        let width = sourceSize.width * scale
        let height = sourceSize.height * scale
        return CGRect(x: destination.midX - crop.midX * width,
                      y: destination.midY - crop.midY * height, width: width, height: height)
    }

    static func matchedHeight(width: Double, height: Double, sourceAspect: CGFloat, crop requested: CGRect) -> Double {
        let crop = normalized(requested)
        guard crop != unit, abs(width - height) <= 0.00001, sourceAspect > 0 else { return height }
        return min(max(width / Double(sourceAspect * crop.width / crop.height), 0.1), 1)
    }
}
