import CoreGraphics
import Foundation

nonisolated struct RecordingCursorMotion: Sendable, Equatable {
    private static let pathReferenceSize = CGSize(width: 1_920, height: 1_080)

    var smoothing: Double?
    var stiffness: Double
    var damping: Double
    var mass: Double

    init(style: RecordingStudioStyle) {
        smoothing = style.cursorSmoothing.flatMap { $0.isFinite ? min(max($0, 0), 2) : nil }
        stiffness = Self.multiplier(style.cursorSpringStiffnessMultiplier)
        damping = Self.multiplier(style.cursorSpringDampingMultiplier)
        mass = Self.multiplier(style.cursorSpringMassMultiplier)
    }

    var isCinematic: Bool {
        matches(stiffness: 1.35 * 0.7 * 0.7, damping: 0.79 * 0.7, mass: 1.29)
    }

    var filtersArtwork: Bool {
        isCinematic || matches(stiffness: 1.35, damping: 0.79, mass: 1.29)
    }

    var glide: SpringConstant {
        guard let smoothing else {
            return SpringConstant(tension: 470, friction: 70, inertia: 3, clampsOvershoot: true)
        }
        guard smoothing > 0 else {
            return SpringConstant(tension: 1_000, friction: 100, inertia: 0)
        }
        let tension: Double
        let friction: Double
        let inertia: Double
        if smoothing <= 0.5 {
            let normalized = smoothing / 0.5
            tension = (760 - normalized * 420) * 1.12
            friction = 34 + normalized * 24
            inertia = 0.85 + normalized * 0.55
        } else {
            let normalized = (smoothing - 0.5) / 1.5
            tension = (340 - normalized * 180) * 1.12
            friction = 58 + normalized * 22
            inertia = 1.35 + normalized * 0.45
        }
        let cinematicWeight = isCinematic ? 1.6 : 1
        return SpringConstant(
            tension: tension * stiffness,
            friction: friction * damping * cinematicWeight,
            inertia: inertia * mass * cinematicWeight,
            clampsOvershoot: true
        )
    }

    func prepare(_ samples: [PointerStreamEvent]) -> [PointerStreamEvent] {
        guard samples.count > 1, filtersArtwork else { return samples }
        var result = samples
        var runs: [(index: Int, artworkID: String?)] = [(0, samples[0].artworkID)]
        for index in samples.indices where samples[index].kind != .press {
            if index == 0 {
                runs[0].artworkID = samples[index].artworkID
            } else if samples[index].artworkID != runs[runs.count - 1].artworkID {
                runs.append((index, samples[index].artworkID))
            }
        }
        var accepted = runs[0].artworkID
        for index in runs.indices {
            let start = runs[index].index
            let end = index + 1 < runs.count ? runs[index + 1].index : samples.count
            let endTime = samples[min(end, samples.count - 1)].time
            if index == 0 || endTime - samples[start].time >= 0.5 {
                accepted = runs[index].artworkID
            }
            for sampleIndex in start..<end {
                result[sampleIndex].artworkID = accepted
            }
        }
        guard isCinematic else { return result }
        var anchor = 0
        for index in 1..<samples.count {
            let sample = samples[index]
            let previous = samples[index - 1]
            if sample.x == previous.x, sample.y == previous.y {
                straighten(samples, result: &result, start: anchor, end: index - 1)
                anchor = index
            } else if index == samples.count - 1 || sample.time - samples[anchor].time >= 0.25
                || sample.kind != .travel {
                straighten(samples, result: &result, start: anchor, end: index)
                anchor = index
            }
        }
        return result
    }

    private func straighten(
        _ samples: [PointerStreamEvent],
        result: inout [PointerStreamEvent],
        start: Int,
        end: Int
    ) {
        var pending = [(start, end)]
        while let (a, b) = pending.popLast() {
            guard b > a + 1 else { continue }
            let span = samples[b].time - samples[a].time
            guard span > 0 else { continue }
            var maximumError = 10.0
            var split: Int?
            for index in (a + 1)..<b {
                let fraction = (samples[index].time - samples[a].time) / span
                let x = samples[a].x + (samples[b].x - samples[a].x) * fraction
                let y = samples[a].y + (samples[b].y - samples[a].y) * fraction
                let error = hypot(
                    (samples[index].x - x) * Self.pathReferenceSize.width,
                    (samples[index].y - y) * Self.pathReferenceSize.height
                )
                if error > maximumError {
                    maximumError = error
                    split = index
                }
            }
            if let split {
                pending.append((a, split))
                pending.append((split, b))
            } else {
                for index in (a + 1)..<b {
                    let fraction = (samples[index].time - samples[a].time) / span
                    result[index].x = samples[a].x + (samples[b].x - samples[a].x) * fraction
                    result[index].y = samples[a].y + (samples[b].y - samples[a].y) * fraction
                }
            }
        }
    }

    private func matches(stiffness: Double, damping: Double, mass: Double) -> Bool {
        guard let smoothing else { return false }
        return abs(smoothing - 0.67) < 0.000001
            && abs(self.stiffness - stiffness) < 0.000001
            && abs(self.damping - damping) < 0.000001
            && abs(self.mass - mass) < 0.000001
    }

    private static func multiplier(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0.25), 3) : 1
    }
}
