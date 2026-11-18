import Foundation
import CoreGraphics

nonisolated enum RecordingZoomAnimationStyle: String, Codable, CaseIterable, Sendable {
    case smooth = "Smooth"
    case dynamic = "Dynamic"

    var spring: SpringConstant {
        switch self {
        case .smooth: SpringConstant(tension: 125, friction: 12, inertia: 1.5, clampsOvershoot: true)
        case .dynamic: SpringConstant(tension: 220, friction: 20, inertia: 1, clampsOvershoot: false)
        }
    }
}

nonisolated enum RecordingMotionPreset: String, CaseIterable, Sendable {
    case focused = "Focused"
    case cinematic = "Cinematic"

    var zoomMotion: RecordingZoomMotionSettings {
        var settings = RecordingZoomMotionSettings()
        if self == .cinematic {
            settings.zoomInDuration = 0.2 / 0.7
            settings.zoomOutDuration = 0.2 / (0.7 * 0.7)
        }
        return settings
    }

    func apply(to appearance: inout RecordingExportAppearance, style: inout RecordingStudioStyle) {
        var settings = appearance.zoomMotion ?? RecordingZoomMotionSettings()
        settings.zoomInDuration = zoomMotion.zoomInDuration
        settings.zoomOutDuration = zoomMotion.zoomOutDuration
        appearance.zoomMotion = settings
        style.cursorScale = 2.5
        style.cursorSmoothing = 0.67
        style.cursorSpringStiffnessMultiplier = self == .cinematic ? 1.35 * 0.7 * 0.7 : 1.35
        style.cursorSpringDampingMultiplier = self == .cinematic ? 0.79 * 0.7 : 0.79
        style.cursorSpringMassMultiplier = 1.29
        style.cursorClickBounce = 2.5
        style.cursorClickBounceDuration = 0.230
    }

    static func matching(appearance: RecordingExportAppearance, style: RecordingStudioStyle) -> Self? {
        guard let motion = appearance.zoomMotion, let smoothing = style.cursorSmoothing,
              let bounce = style.cursorClickBounce else { return nil }
        func equal(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.000_001 }
        return allCases.first {
            equal(motion.zoomInDuration, $0.zoomMotion.zoomInDuration)
                && equal(motion.zoomOutDuration, $0.zoomMotion.zoomOutDuration)
                && equal(Double(style.cursorScale), 2.5) && equal(smoothing, 0.67)
                && equal(style.cursorSpringStiffnessMultiplier, $0 == .cinematic ? 1.35 * 0.7 * 0.7 : 1.35)
                && equal(style.cursorSpringDampingMultiplier, $0 == .cinematic ? 0.79 * 0.7 : 0.79)
                && equal(style.cursorSpringMassMultiplier, 1.29) && equal(bounce, 2.5)
                && equal(style.cursorClickBounceDuration, 0.230)
        }
    }
}
