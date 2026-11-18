import CoreGraphics
import Foundation

nonisolated struct StudioScreenMotionBlur: Equatable, Sendable {
    static let defaultAmount = 0.35

    enum Mode: UInt32, Sendable {
        case none, pan, radial
    }

    var mode: Mode = .none
    var velocity: CGPoint = .zero
    var center: CGPoint = .zero
    var strength: Double = 0
    var offset: Double = 0
    var isActive: Bool { mode != .none }

    var parameters: [SIMD4<Float>] {
        [
            SIMD4(Float(mode.rawValue), Float(velocity.x), Float(velocity.y), Float(strength)),
            SIMD4(Float(center.x), Float(center.y), Float(offset), 0)
        ]
    }

    func scaled(by scale: CGFloat, origin: CGPoint = .zero) -> Self {
        var result = self
        result.velocity = CGPoint(x: velocity.x * scale, y: velocity.y * scale)
        result.center = CGPoint(x: (center.x - origin.x) * scale, y: (center.y - origin.y) * scale)
        result.offset *= scale
        return result
    }

    func draw(_ image: CGImage, in rect: CGRect, canvasHeight: CGFloat, context: CGContext) {
        let flipped = CGRect(x: rect.minX, y: canvasHeight - rect.maxY, width: rect.width, height: rect.height)
        guard isActive else {
            context.draw(image, in: flipped)
            return
        }
        context.saveGState()
        context.clip(to: flipped)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        context.setBlendMode(.plusLighter)
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let strips = (0..<3).map { row in
            (0..<3).map { column in
                image.cropping(to: CGRect(
                    x: column == 2 ? width - 1 : 0,
                    y: row == 0 ? height - 1 : 0,
                    width: column == 1 ? width : 1,
                    height: row == 1 ? height : 1
                ))
            }
        }
        if mode == .pan {
            let magnitude = hypot(velocity.x, velocity.y)
            let shift = -offset / magnitude - 0.5
            for i in -1..<12 {
                let fraction = i < 0 ? 0 : Double(i) / 12 + shift
                context.setAlpha(1 / 13.0)
                Self.drawClamped(
                    strips, in: flipped.offsetBy(dx: -velocity.x * fraction, dy: velocity.y * fraction), context: context
                )
            }
        } else {
            let weights = (0..<32).map { index in
                let percent = (Double(index) + 0.5) / 32
                return 4 * (percent - percent * percent)
            }
            let total = weights.reduce(0, +)
            let pivot = CGPoint(x: center.x, y: canvasHeight - center.y)
            for i in 0..<32 {
                let factor = 1 - strength * (Double(i) + 0.5) / 32
                let divisor = abs(factor) < 0.00001 ? 0.00001 : factor
                context.saveGState()
                context.setAlpha(weights[i] / total)
                context.translateBy(x: pivot.x, y: pivot.y)
                context.scaleBy(x: 1 / divisor, y: 1 / divisor)
                context.translateBy(x: -pivot.x, y: -pivot.y)
                Self.drawClamped(strips, in: flipped, context: context)
                context.restoreGState()
            }
        }
        context.endTransparencyLayer()
        context.restoreGState()
    }

    private static func drawClamped(_ strips: [[CGImage?]], in rect: CGRect, context: CGContext) {
        let clip = context.boundingBoxOfClipPath
        let xs = [min(clip.minX, rect.minX), rect.minX, rect.maxX, max(clip.maxX, rect.maxX)]
        let ys = [min(clip.minY, rect.minY), rect.minY, rect.maxY, max(clip.maxY, rect.maxY)]
        for row in 0..<3 {
            for column in 0..<3 {
                let destination = CGRect(
                    x: xs[column], y: ys[row], width: xs[column + 1] - xs[column], height: ys[row + 1] - ys[row]
                )
                if destination.width > 0, destination.height > 0, let image = strips[row][column] {
                    context.draw(image, in: destination)
                }
            }
        }
    }

    static func analyze(
        previous: CGRect, current: CGRect, deltaSeconds: TimeInterval,
        stageSize: CGSize, amount: Double = defaultAmount, shutterFraction: Double = 1,
        panVelocityThreshold: Double = 0, zoomVelocityThreshold: Double = 0,
        maxDirectionalBlurPx: Double = 41.8, maxRadialBlurStrength: Double = 1
    ) -> Self {
        guard deltaSeconds.isFinite, deltaSeconds > 0, deltaSeconds <= 0.1,
              amount.isFinite, amount > 0, shutterFraction.isFinite, shutterFraction > 0,
              [previous, current].allSatisfy({
                  $0.minX.isFinite && $0.minY.isFinite && $0.width.isFinite && $0.height.isFinite
                      && $0.width > 0 && $0.height > 0
              }) else { return Self() }
        let dx = current.midX - previous.midX
        let dy = current.midY - previous.midY
        let moveDistance = hypot(dx, dy)
        let sizeDistance = hypot(current.width - previous.width, current.height - previous.height)
        let previousDiagonal = hypot(previous.width, previous.height)
        let currentDiagonal = hypot(current.width, current.height)
        let zoomVelocity = abs(log(currentDiagonal / previousDiagonal)) / max(0.0001, deltaSeconds)
        let panActive = moveDistance > 0.001
            && moveDistance / max(0.0001, deltaSeconds) > min(max(panVelocityThreshold, 0), 240)
        let zoomActive = sizeDistance > 0.001 && zoomVelocity > min(max(zoomVelocityThreshold, 0), 0.4)
        guard panActive || zoomActive else { return Self() }
        let fpsScale = 1 / max(1 / 240.0, deltaSeconds) / 60
        let exposure = min(amount, 2) * fpsScale * min(shutterFraction, 1)
        if zoomActive && (!panActive || sizeDistance > moveDistance) {
            return Self(
                mode: .radial,
                center: zoomCenter(previous: previous, current: current, stageSize: stageSize),
                strength: abs(1 - currentDiagonal / previousDiagonal) * exposure * 4
                    * min(max(maxRadialBlurStrength, 0), 1.5)
            )
        }
        let scale = exposure * 3 * min(max(maxDirectionalBlurPx, 0), 96) / 41.8
        let velocity = CGPoint(x: dx * scale, y: dy * scale)
        let magnitude = hypot(velocity.x, velocity.y)
        guard magnitude >= 0.01 else { return Self() }
        return Self(mode: .pan, velocity: velocity, offset: -magnitude / 32)
    }

    private static func zoomCenter(previous: CGRect, current: CGRect, stageSize: CGSize) -> CGPoint {
        let a = [
            CGPoint(x: previous.minX, y: previous.minY), CGPoint(x: previous.maxX, y: previous.minY),
            CGPoint(x: previous.maxX, y: previous.maxY), CGPoint(x: previous.minX, y: previous.maxY)
        ]
        let b = [
            CGPoint(x: current.minX, y: current.minY), CGPoint(x: current.maxX, y: current.minY),
            CGPoint(x: current.maxX, y: current.maxY), CGPoint(x: current.minX, y: current.maxY)
        ]
        for i in 0..<3 where hypot(b[i].x - a[i].x, b[i].y - a[i].y) >= 0.5 {
            for j in (i + 1)..<4 where hypot(b[j].x - a[j].x, b[j].y - a[j].y) >= 0.5 {
                let u = CGPoint(x: b[i].x - a[i].x, y: b[i].y - a[i].y)
                let v = CGPoint(x: b[j].x - a[j].x, y: b[j].y - a[j].y)
                let denominator = u.x * v.y - u.y * v.x
                guard abs(denominator) >= 0.0001 else { continue }
                let t = ((a[j].x - a[i].x) * v.y - (a[j].y - a[i].y) * v.x) / denominator
                return CGPoint(
                    x: min(max(a[i].x + u.x * t, -stageSize.width), stageSize.width * 2),
                    y: min(max(a[i].y + u.y * t, -stageSize.height), stageSize.height * 2)
                )
            }
        }
        return CGPoint(x: current.midX, y: current.midY)
    }
}

nonisolated struct StudioScreenMotionBlurPlayback {
    private var previous: (time: TimeInterval, rect: CGRect)?
    private var current = StudioScreenMotionBlur()

    mutating func sample(
        at time: TimeInterval, rect: CGRect, stageSize: CGSize, isPlaying: Bool, shutterFraction: Double
    ) -> StudioScreenMotionBlur {
        guard isPlaying, time.isFinite, shutterFraction.isFinite, shutterFraction > 0 else {
            previous = nil
            current = StudioScreenMotionBlur()
            return current
        }
        defer { previous = (time, rect) }
        guard let previous else { return current }
        let delta = time - previous.time
        if delta == 0, previous.rect == rect { return current }
        current = StudioScreenMotionBlur.analyze(
            previous: previous.rect, current: rect, deltaSeconds: delta,
            stageSize: stageSize, shutterFraction: shutterFraction
        )
        return current
    }
}
