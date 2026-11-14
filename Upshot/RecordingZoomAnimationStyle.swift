import Foundation

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
