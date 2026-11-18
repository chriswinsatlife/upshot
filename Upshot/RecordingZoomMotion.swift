import CoreGraphics
import Foundation

nonisolated struct RecordingZoomMotionSettings: Codable, Equatable, Sendable {
    var zoomInDuration: TimeInterval = 0.2
    var zoomOutDuration: TimeInterval = 0.2 / 0.7
    var connectZooms = true
    var connectedZoomGap: TimeInterval = 1.5
    var connectedZoomDuration: TimeInterval = 1

    init() {}

    private enum CodingKeys: String, CodingKey {
        case zoomInDuration, zoomOutDuration, connectZooms, connectedZoomGap, connectedZoomDuration
    }

    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        zoomInDuration = Self.duration(try values.decodeIfPresent(Double.self, forKey: .zoomInDuration), fallback: 0.2)
        zoomOutDuration = Self.duration(try values.decodeIfPresent(Double.self, forKey: .zoomOutDuration), fallback: 0.2 / 0.7)
        connectZooms = try values.decodeIfPresent(Bool.self, forKey: .connectZooms) ?? true
        let gap = try values.decodeIfPresent(Double.self, forKey: .connectedZoomGap) ?? 1.5
        connectedZoomGap = gap.isFinite ? min(max(gap, 0), 5) : 1.5
        connectedZoomDuration = Self.duration(try values.decodeIfPresent(Double.self, forKey: .connectedZoomDuration), fallback: 1)
    }

    var isCinematic: Bool {
        abs(zoomInDuration - 0.2 / 0.7) < 0.000_001
            && abs(zoomOutDuration - 0.2 / (0.7 * 0.7)) < 0.000_001
    }

    var cameraSpring: SpringConstant {
        SpringConstant(tension: 100, friction: isCinematic ? 21 * sqrt(1.6) : 21,
                       inertia: isCinematic ? 1.6 : 1, clampsOvershoot: true)
    }

    static func duration(_ value: Double?, fallback: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return min(max(value, 0.06), 4)
    }
}

nonisolated struct RecordingZoomTransitionProfile: Sendable {
    private let samples: [Double]
    let duration: TimeInterval
    private static let stepRate = 240.0

    init(targetDuration: TimeInterval, cinematic: Bool) {
        let targetDuration = RecordingZoomMotionSettings.duration(targetDuration, fallback: 0.2)
        let profile = SpringConstant(tension: 100, friction: cinematic ? 21 * sqrt(1.6) : 21,
                                     inertia: cinematic ? 1.6 : 1, clampsOvershoot: true)
        var spring = DampedSpring(position: 0)
        var values = [0.0]
        let dt = 1 / Self.stepRate
        for index in 1...Int(ceil((targetDuration + 3) * Self.stepRate)) {
            let time = Double(index) * dt
            spring.step(toward: Self.easeOut(time / targetDuration), using: profile, dt: dt)
            values.append(spring.position)
            if time >= targetDuration, spring.position >= 0.999 { break }
        }
        let final = max(values.last ?? 1, 0.000_001)
        samples = values.map { min(max($0 / final, 0), 1) }
        duration = Double(values.count - 1) * dt
    }

    func value(at elapsed: TimeInterval) -> Double {
        guard elapsed > 0 else { return 0 }
        guard elapsed < duration else { return 1 }
        let position = elapsed * Self.stepRate
        let index = min(Int(position), samples.count - 2)
        return samples[index] + (samples[index + 1] - samples[index]) * (position - Double(index))
    }

    static func easeOut(_ progress: Double) -> Double {
        guard progress > 0 else { return 0 }
        guard progress < 1 else { return 1 }
        let progress = min(max(progress, 0), 1)
        var lower = 0.0
        var upper = 1.0
        for _ in 0..<24 {
            let t = (lower + upper) / 2
            let inverse = 1 - t
            let x = 3 * 0.16 * inverse * inverse * t + 3 * 0.3 * inverse * t * t + t * t * t
            if x < progress { lower = t } else { upper = t }
        }
        let t = (lower + upper) / 2
        return 1 - pow(1 - t, 3)
    }
}

nonisolated struct RecordingZoomEnvelopePlan: Sendable {
    struct Region: Sendable {
        var cue: ZoomCue
        var start: TimeInterval
        var end: TimeInterval
    }

    struct Sample: Sendable {
        let cue: ZoomCue
        let outgoing: ZoomCue?
        let panProgress: Double
        let magnification: Double
        let strength: Double
        let zoomingOut: Bool
        let connected: Bool
        let holdsIncoming: Bool
    }

    private let regions: [Region]
    private let connections: Set<Int>
    private let entry: RecordingZoomTransitionProfile
    private let exit: RecordingZoomTransitionProfile
    private let settings: RecordingZoomMotionSettings

    init(cues: [ZoomCue], timeline: RecordingClipTimeline, settings: RecordingZoomMotionSettings) {
        self.settings = settings
        entry = RecordingZoomTransitionProfile(targetDuration: settings.zoomInDuration, cinematic: settings.isCinematic)
        exit = RecordingZoomTransitionProfile(targetDuration: settings.zoomOutDuration, cinematic: settings.isCinematic)
        var mapped: [Region] = []
        for cue in cues where cue.isEnabled && cue.start.isFinite && cue.end.isFinite && cue.end > cue.start {
            let slices = timeline.slices(overlapping: cue.start, sourceEnd: cue.end)
            for slice in slices {
                if let last = mapped.last, last.cue.id == cue.id, abs(last.end - slice.editorStart) < 0.000_001 {
                    mapped[mapped.count - 1].end = slice.editorEnd
                } else {
                    mapped.append(Region(cue: cue, start: slice.editorStart, end: slice.editorEnd))
                }
            }
        }
        mapped.sort { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }
        regions = mapped
        var pairs = Set<Int>()
        if settings.connectZooms, mapped.count > 1 {
            let limit = settings.connectedZoomGap.isFinite ? min(max(settings.connectedZoomGap, 0), 1.5) : 1.5
            for index in (0..<(mapped.count - 1)).reversed() {
                let current = mapped[index]
                let next = mapped[index + 1]
                let gap = next.start - current.end
                guard gap > 0, gap <= limit, !current.cue.skipsEasing, !next.cue.skipsEasing else { continue }
                let destinationEnd = max(next.end, next.start + exit.duration)
                if destinationEnd > next.end, index + 2 < mapped.count,
                   mapped[index + 2].start < destinationEnd, !pairs.contains(index + 1) { continue }
                pairs.insert(index)
            }
        }
        connections = pairs
    }

    func sample(at time: TimeInterval) -> Sample? {
        var selected: (index: Int, sample: Sample)?
        for index in regions.indices {
            let region = regions[index]
            let incoming = index > 0 && connections.contains(index - 1)
            let outgoing = connections.contains(index)
            let activeStart = incoming ? regions[index - 1].end : region.start
            let activeEnd = incoming && !outgoing ? max(region.end, region.start + exit.duration) : region.end
            guard time >= activeStart, time <= activeEnd else { continue }
            var first = index
            var last = index
            while first > 0 && connections.contains(first - 1) { first -= 1 }
            while connections.contains(last) { last += 1 }
            let chainEnd = first == last ? regions[last].end : max(regions[last].end, regions[last].start + exit.duration)
            func strength(_ time: Double) -> Double {
                guard time > regions[first].start, time < chainEnd else { return 0 }
                if region.cue.skipsEasing { return 1 }
                return entry.value(at: time - regions[first].start)
                    * (1 - exit.value(at: time - (chainEnd - exit.duration)))
            }
            let amount = strength(time)
            let previous = incoming ? regions[index - 1] : nil
            let panDuration = RecordingZoomMotionSettings.duration(settings.connectedZoomDuration, fallback: 1)
            let panEnd = previous.map { min(region.start, $0.end + panDuration) } ?? region.start
            let progress = previous.map {
                RecordingZoomTransitionProfile.easeOut((time - $0.end) / max(panEnd - $0.end, 0.000_001))
            } ?? 1
            let scale = previous.map { $0.cue.zoom + (region.cue.zoom - $0.cue.zoom) * progress } ?? region.cue.zoom
            let sample = Sample(cue: region.cue, outgoing: time < panEnd ? previous?.cue : nil,
                                panProgress: progress, magnification: max(1, scale), strength: amount,
                                zoomingOut: strength(time + 0.0005) < strength(time - 0.0005),
                                connected: incoming && time < region.start,
                                holdsIncoming: incoming && time >= panEnd && time < region.start)
            if let existing = selected {
                let priority = Self.priority(region.cue)
                let previousPriority = Self.priority(existing.sample.cue)
                if priority < previousPriority || (priority == previousPriority && region.cue.start < existing.sample.cue.start) { continue }
            }
            selected = (index, sample)
        }
        return selected?.sample
    }

    private static func priority(_ cue: ZoomCue) -> Int {
        if cue.isImplicit { return 0 }
        switch cue.anchorMode {
        case .pointerAnchor, .safeZone: return 1
        case .smartAnchor: return 2
        case .pinnedAnchor: return 3
        }
    }
}
