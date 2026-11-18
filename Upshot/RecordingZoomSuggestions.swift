import CoreGraphics
import Foundation

nonisolated enum RecordingZoomAmount {
    static let presets: [Double] = [1.25, 1.5, 1.8, 2.2, 3.5, 5]
    static let defaultValue = 1.8
    static let maximum = 5.0
}

nonisolated enum RecordingZoomSuggestionStatus: String, Sendable {
    case ok
    case noTelemetry = "no-telemetry"
    case noInteractions = "no-interactions"
    case noSlots = "no-slots"
}

nonisolated struct RecordingZoomSuggestionResult: Sendable {
    var status: RecordingZoomSuggestionStatus
    var cues: [ZoomCue] = []
    var classifications: [String: Int] = [:]
}

nonisolated extension ZoomCueSynthesizer {
    private enum Interaction: String {
        case doubleClick = "double-click-like"
        case dropdown = "dropdown-open"
        case textSelection = "text-selection"
        case textField = "text-field-click"
        case click = "click-like"

        var strength: Int {
            switch self {
            case .doubleClick: 1500
            case .dropdown: 1200
            case .textSelection: 1300
            case .textField: 1100
            case .click: 900
            }
        }
    }

    private struct PressInterval {
        var down: PointerPressEvent
        var up: PointerPressEvent?
    }

    private struct Candidate {
        var start: TimeInterval
        var end: TimeInterval
        var focus: CGPoint
        var interaction: Interaction
    }

    private struct Cluster {
        var start: TimeInterval
        var end: TimeInterval
        var anchor: Candidate
    }

    private struct Window {
        var start: TimeInterval
        var end: TimeInterval
        var anchor: Candidate
        var segment: RecordingClipSegment
        var editorStart: TimeInterval
        var editorEnd: TimeInterval
    }

    static func usableSampleCount(in capture: PointerCaptureFile) -> Int {
        capture.travel.filter { valid(time: $0.time, x: $0.x, y: $0.y) }.count
            + capture.presses.filter { valid(time: $0.time, x: $0.x, y: $0.y) }.count
    }

    static func suggestions(
        from capture: PointerCaptureFile,
        duration: TimeInterval,
        clipTimeline: RecordingClipTimeline? = nil,
        reservedCues: [ZoomCue] = []
    ) -> RecordingZoomSuggestionResult {
        guard duration.isFinite, duration > 0 else { return .init(status: .noSlots) }
        let timeline = clipTimeline ?? .full(sourceDuration: duration)
        guard timeline.duration.isFinite, timeline.duration > 0 else { return .init(status: .noSlots) }
        let presses = normalizedPresses(capture.presses, duration: duration)
        let travel = capture.travel
            .filter { valid(time: $0.time, x: $0.x, y: $0.y) }
            .map { sample in
                var sample = sample
                sample.time = min(max(sample.time, 0), duration)
                sample.x = min(max(sample.x, 0), 1)
                sample.y = min(max(sample.y, 0), 1)
                return sample
            }
            .sorted { $0.time < $1.time }
        guard !travel.isEmpty || !presses.isEmpty,
              travel.count + presses.count > 1 || presses.contains(where: { $0.phase == .down }) else {
            return .init(status: .noTelemetry)
        }

        let intervals = pressIntervals(presses)
        var counts: [String: Int] = [:]
        var previousPresses: [Int: PressInterval] = [:]
        let candidates = intervals.map { interval in
            let interaction = classify(interval, previous: previousPresses[interval.down.button], travel: travel)
            previousPresses[interval.down.button] = interval
            counts[interaction.rawValue, default: 0] += 1
            return Candidate(
                start: interval.down.time,
                end: interval.up?.time ?? duration,
                focus: CGPoint(x: interval.down.x, y: interval.down.y),
                interaction: interaction
            )
        }

        var reserved = reservedCues.flatMap { cue in
            timeline.slices(overlapping: cue.start, sourceEnd: cue.end).map { $0.editorStart...$0.editorEnd }
        }
        var windows: [Window] = []
        var editorStart: TimeInterval = 0
        var retainedCount = 0
        for segment in timeline.segments {
            let editorEnd = editorStart + segment.editorDuration
            let projected = candidates.compactMap { candidate -> Candidate? in
                guard candidate.start < segment.sourceEnd,
                      candidate.end >= segment.sourceStart,
                      candidate.end != segment.sourceStart || candidate.start >= segment.sourceStart else { return nil }
                var candidate = candidate
                candidate.start = editorStart + (max(candidate.start, segment.sourceStart) - segment.sourceStart) / segment.speed
                candidate.end = editorStart + (min(candidate.end, segment.sourceEnd) - segment.sourceStart) / segment.speed
                return candidate
            }
            retainedCount += projected.count
            for cluster in clusters(projected) {
                let start = max(editorStart, cluster.start - 0.5)
                let end = min(editorEnd, cluster.end + 0.5)
                guard end > start,
                      !reserved.contains(where: { overlaps(start: start, end: end, span: $0) }) else { continue }
                windows.append(Window(
                    start: start,
                    end: end,
                    anchor: cluster.anchor,
                    segment: segment,
                    editorStart: editorStart,
                    editorEnd: editorEnd
                ))
            }
            editorStart = editorEnd
        }
        guard retainedCount > 0 else { return .init(status: .noInteractions, classifications: counts) }

        var cues: [ZoomCue] = []
        let defaultDuration = min(2, timeline.duration)
        for (index, window) in windows.enumerated() {
            let blockers = reserved + windows.dropFirst(index + 1).map { $0.start...$0.end }
            let halfDuration = max(defaultDuration / 2, max(window.anchor.start - window.start, window.end - window.anchor.start))
            let centeredStart = window.anchor.start - halfDuration
            let centeredEnd = window.anchor.start + halfDuration
            let canCenter = centeredStart >= window.editorStart && centeredEnd <= window.editorEnd
                && !blockers.contains { overlaps(start: centeredStart - 0.5, end: centeredEnd + 0.5, span: $0) }
            let lower = blockers.filter { $0.upperBound <= window.start }
                .reduce(window.editorStart) { max($0, $1.upperBound + 0.5) }
            let upper = blockers.filter { $0.lowerBound >= window.end }
                .reduce(window.editorEnd) { min($0, $1.lowerBound - 0.5) }
            let length = min(max(defaultDuration, window.end - window.start), upper - lower)
            let minStart = max(lower, window.end - length)
            let maxStart = min(window.start, upper - length)
            let canExpand = length >= window.end - window.start && minStart <= maxStart
            let expandedStart = max(minStart, min(window.anchor.start - length / 2, maxStart))
            let start = canCenter ? centeredStart : (canExpand ? expandedStart : window.start)
            let end = canCenter ? centeredEnd : (canExpand ? expandedStart + length : window.end)
            guard end > start, !reserved.contains(where: { overlaps(start: start, end: end, span: $0) }) else { continue }
            let sourceStart = window.segment.sourceStart + (start - window.editorStart) * window.segment.speed
            let sourceEnd = min(window.segment.sourceEnd, window.segment.sourceStart + (end - window.editorStart) * window.segment.speed)
            guard sourceEnd - sourceStart >= ZoomCue.minimumDuration else { continue }
            cues.append(ZoomCue(
                start: sourceStart,
                end: sourceEnd,
                zoom: RecordingZoomAmount.defaultValue,
                anchorMode: .safeZone,
                pinnedPoint: window.anchor.focus,
                boundsBias: 0.25
            ))
            reserved.append(start...end)
        }
        return .init(status: cues.isEmpty ? .noSlots : .ok, cues: cues.sorted { $0.start < $1.start }, classifications: counts)
    }

    private static func valid(time: Double, x: Double, y: Double) -> Bool {
        time.isFinite && x.isFinite && y.isFinite
    }

    private static func normalizedPresses(_ presses: [PointerPressEvent], duration: TimeInterval) -> [PointerPressEvent] {
        presses.enumerated()
            .filter { valid(time: $0.element.time, x: $0.element.x, y: $0.element.y) }
            .sorted {
                $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time
            }
            .map { _, press in
                var press = press
                press.time = min(max(press.time, 0), duration)
                press.x = min(max(press.x, 0), 1)
                press.y = min(max(press.y, 0), 1)
                return press
            }
    }

    private static func pressIntervals(_ presses: [PointerPressEvent]) -> [PressInterval] {
        var intervals: [PressInterval] = []
        var active: [Int: Int] = [:]
        for press in presses {
            if let index = active.removeValue(forKey: press.button) {
                intervals[index].up = press
            }
            if press.phase == .down {
                active[press.button] = intervals.count
                intervals.append(PressInterval(down: press))
            }
        }
        return intervals
    }

    private static func classify(_ interval: PressInterval, previous: PressInterval?, travel: [PointerTravelSample]) -> Interaction {
        let down = interval.down
        if let previous, previous.down.button == down.button,
           down.time - previous.down.time <= 0.45,
           hypot(down.x - previous.down.x, down.y - previous.down.y) <= 0.035 {
            return .doubleClick
        }
        if let up = interval.up {
            let dx = abs(up.x - down.x)
            let dy = abs(up.y - down.y)
            if up.time - down.time >= 0.2, dx > 0.03, dx > dy * 1.8 { return .textSelection }
        }
        let moves = travel.filter { $0.time > down.time + 0.1 && $0.time <= down.time + 2 }
        guard moves.count >= 3 else { return .textField }
        var distance: Double = 0
        var dx: Double = 0
        var dy: Double = 0
        for sample in moves {
            distance = max(distance, hypot(sample.x - down.x, sample.y - down.y))
            dx += abs(sample.x - down.x)
            dy += abs(sample.y - down.y)
        }
        if distance < 0.02 { return .textField }
        if let last = moves.last, last.y - down.y > 0.03, dy > dx * 1.5 { return .dropdown }
        if dx > 0.03, dx > dy * 1.8 { return .textSelection }
        return .click
    }

    private static func clusters(_ candidates: [Candidate]) -> [Cluster] {
        var result: [Cluster] = []
        for candidate in candidates {
            if var cluster = result.last, candidate.start - cluster.end <= 2.5 {
                cluster.end = max(cluster.end, candidate.end)
                if candidate.interaction.strength > cluster.anchor.interaction.strength { cluster.anchor = candidate }
                result[result.count - 1] = cluster
            } else {
                result.append(Cluster(start: candidate.start, end: candidate.end, anchor: candidate))
            }
        }
        return result
    }

    private static func overlaps(start: TimeInterval, end: TimeInterval, span: ClosedRange<TimeInterval>) -> Bool {
        end > span.lowerBound && start < span.upperBound
    }
}
