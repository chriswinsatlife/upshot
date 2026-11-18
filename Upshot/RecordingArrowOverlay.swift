import CoreGraphics
import Foundation

nonisolated struct RecordingArrowOverlay: Identifiable, Codable, Equatable, Hashable, Sendable {
    enum Direction: String, Codable, CaseIterable, Identifiable, Sendable {
        case up, down, left, right
        case upRight = "up-right"
        case upLeft = "up-left"
        case downRight = "down-right"
        case downLeft = "down-left"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .up: "Up"
            case .down: "Down"
            case .left: "Left"
            case .right: "Right"
            case .upRight: "Up Right"
            case .upLeft: "Up Left"
            case .downRight: "Down Right"
            case .downLeft: "Down Left"
            }
        }

        var segments: [(CGPoint, CGPoint)] {
            let points: [(CGFloat, CGFloat, CGFloat, CGFloat)] = switch self {
            case .up: [(50, 20, 50, 80), (50, 20, 35, 35), (50, 20, 65, 35)]
            case .down: [(50, 20, 50, 80), (50, 80, 35, 65), (50, 80, 65, 65)]
            case .left: [(80, 50, 20, 50), (20, 50, 35, 35), (20, 50, 35, 65)]
            case .right: [(20, 50, 80, 50), (80, 50, 65, 35), (80, 50, 65, 65)]
            case .upRight: [(25, 75, 75, 25), (75, 25, 60, 30), (75, 25, 70, 40)]
            case .upLeft: [(75, 75, 25, 25), (25, 25, 40, 30), (25, 25, 30, 40)]
            case .downRight: [(25, 25, 75, 75), (75, 75, 70, 60), (75, 75, 60, 70)]
            case .downLeft: [(75, 25, 25, 75), (25, 75, 30, 60), (25, 75, 40, 70)]
            }
            return points.map { (CGPoint(x: $0.0, y: $0.1), CGPoint(x: $0.2, y: $0.3)) }
        }
    }

    static let defaultDuration: TimeInterval = 3
    static let minimumDuration: TimeInterval = 0.1
    var id = UUID()
    var start: TimeInterval
    var end: TimeInterval
    var rect = CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)
    var coordinateSpace: RecordingOverlayCoordinateSpace = .recording
    var direction: Direction = .right
    var color = RecordingOverlayColor(red: 37 / 255.0, green: 99 / 255.0, blue: 235 / 255.0)
    var strokeWidth: Double = 4

    init(start: TimeInterval, end: TimeInterval) {
        self.start = start
        self.end = end
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        start = try container.decode(TimeInterval.self, forKey: .start)
        end = try container.decode(TimeInterval.self, forKey: .end)
        rect = try container.decodeIfPresent(CGRect.self, forKey: .rect) ?? rect
        coordinateSpace = try container.decodeIfPresent(RecordingOverlayCoordinateSpace.self, forKey: .coordinateSpace) ?? .recording
        direction = try container.decodeIfPresent(Direction.self, forKey: .direction) ?? .right
        color = try container.decodeIfPresent(RecordingOverlayColor.self, forKey: .color) ?? color
        strokeWidth = try container.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 4
    }

    func isActive(atSourceTime time: TimeInterval) -> Bool {
        time >= start && time < end
    }

    func rect(in reference: CGRect) -> CGRect {
        CGRect(
            x: reference.minX + rect.minX * reference.width,
            y: reference.minY + rect.minY * reference.height,
            width: rect.width * reference.width,
            height: rect.height * reference.height
        )
    }
}

nonisolated enum RecordingArrowOverlayRenderer {
    static func draw(_ overlay: RecordingArrowOverlay, canvasSize: CGSize, in context: CGContext) {
        let rect = overlay.rect(in: CGRect(origin: .zero, size: canvasSize))
        let padding = 8 * canvasSize.width / 1920
        let scale = min(max(0, rect.width - padding * 2), max(0, rect.height - padding * 2)) / 100
        guard scale > 0 else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: rect.midX - 50 * scale, y: rect.midY - 50 * scale)
        let offset = context.convertToDeviceSpace(CGSize(width: 0, height: 4 * scale))
        let blur = context.convertToDeviceSpace(CGSize(width: 8 * scale, height: 0))
        context.setShadow(offset: offset, blur: hypot(blur.width, blur.height), color: CGColor(gray: 0, alpha: 0.3))
        context.setStrokeColor(overlay.color.cgColor)
        context.setLineWidth(CGFloat(min(max(overlay.strokeWidth, 1), 6)) * scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.beginPath()
        for (start, end) in overlay.direction.segments {
            context.move(to: CGPoint(x: start.x * scale, y: start.y * scale))
            context.addLine(to: CGPoint(x: end.x * scale, y: end.y * scale))
        }
        context.strokePath()
    }
}
