import Foundation

nonisolated struct StrokeOptions {
    struct End {
        var cap: Bool = true
        var taper: Double? = nil
        var easing: ((Double) -> Double)? = nil
    }

    var size: Double = 16
    var thinning: Double = 0.5
    var smoothing: Double = 0.5
    var streamline: Double = 0.5
    var easing: (Double) -> Double = { $0 }
    var simulatePressure: Bool = true
    var start = End()
    var end = End()
    var last: Bool = false
}

nonisolated func resolveTaper(_ taper: Double?, _ size: Double, _ totalLength: Double) -> Double {
    guard let taper, taper != 0 else { return 0 }
    return taper.isInfinite ? Swift.max(size, totalLength) : taper
}

nonisolated enum FreehandSettings {
    static let penEasing: (Double) -> Double = { t in t * 0.65 + sin((t * PI) / 2) * 0.35 }

    static func simulatePressure(_ strokeWidth: Double) -> StrokeOptions {
        StrokeOptions(
            size: strokeWidth,
            thinning: 0.5,
            smoothing: 0.62,
            streamline: modulate(strokeWidth, (9, 16), (0.64, 0.74), true),
            easing: Easings.easeOutSine,
            simulatePressure: true
        )
    }

    static func realPressure(_ strokeWidth: Double) -> StrokeOptions {
        StrokeOptions(
            size: 1 + strokeWidth * 1.2,
            thinning: 0.62,
            smoothing: 0.62,
            streamline: 0.62,
            easing: penEasing,
            simulatePressure: false
        )
    }

    static func solid(_ strokeWidth: Double) -> StrokeOptions {
        StrokeOptions(
            size: strokeWidth,
            thinning: 0,
            smoothing: 0.62,
            streamline: modulate(strokeWidth, (9, 16), (0.64, 0.74), true),
            easing: Easings.linear,
            simulatePressure: false
        )
    }

    static func solidRealPressure(_ strokeWidth: Double) -> StrokeOptions {
        StrokeOptions(
            size: strokeWidth,
            thinning: 0,
            smoothing: 0.62,
            streamline: 0.62,
            easing: Easings.linear,
            simulatePressure: false
        )
    }

    static func forDrawShape(
        isPen: Bool,
        isComplete: Bool,
        strokeWidth: Double,
        forceComplete: Bool,
        forceSolid: Bool,
        smoothing: Double? = nil
    ) -> StrokeOptions {
        let last = isComplete || forceComplete
        var options: StrokeOptions
        if forceSolid {
            options = isPen ? solidRealPressure(strokeWidth) : solid(strokeWidth)
        } else if isPen {
            options = realPressure(strokeWidth)
        } else {
            options = simulatePressure(strokeWidth)
        }
        if let smoothing {
            options.smoothing = min(1, max(0, smoothing))
            if options.smoothing != 0.62 { options.streamline = options.smoothing }
        }
        options.last = last
        return options
    }
}
