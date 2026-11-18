import CryptoKit
import Foundation

nonisolated extension RecordingClipTimeline {
    nonisolated struct EditorRegion: Sendable {
        var segmentID: UUID
        var start: TimeInterval
        var end: TimeInterval

        func fragmentID(for itemID: UUID) -> UUID {
            let bytes = Array(SHA256.hash(data: Data((itemID.uuidString + segmentID.uuidString).utf8)))
            return UUID(uuid: (
                bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
            ))
        }
    }

    func editorRegions(overlapping sourceStart: TimeInterval, sourceEnd: TimeInterval) -> [EditorRegion] {
        var result: [EditorRegion] = []
        for slice in slices(overlapping: sourceStart, sourceEnd: sourceEnd) {
            if let last = result.last, slice.editorStart - last.end <= 0.000_001 {
                result[result.count - 1].end = slice.editorEnd
            } else {
                result.append(EditorRegion(segmentID: slice.segmentID, start: slice.editorStart, end: slice.editorEnd))
            }
        }
        return result
    }

    func editorTimes(forSourceEventTime sourceTime: TimeInterval) -> [TimeInterval] {
        guard sourceTime.isFinite else { return [] }
        var result: [TimeInterval] = []
        var editorStart: TimeInterval = 0
        for segment in segments {
            if sourceTime >= segment.sourceStart, sourceTime < segment.sourceEnd {
                result.append(editorStart + (sourceTime - segment.sourceStart) / segment.speed)
            }
            editorStart += segment.editorDuration
        }
        return result
    }

    func reordering(segmentID: UUID, to sequenceIndex: Int) -> RecordingClipTimeline {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else { return self }
        var next = segments
        let segment = next.remove(at: index)
        next.insert(segment, at: min(max(sequenceIndex, 0), next.count))
        return RecordingClipTimeline(segments: next)
    }

    func sequenceIndex(for segmentID: UUID, editorDelta: TimeInterval) -> Int? {
        guard editorDelta.isFinite, let range = editorRange(for: segmentID) else { return nil }
        let center = (range.lowerBound + range.upperBound) / 2 + editorDelta
        var editorStart: TimeInterval = 0
        var insertionIndex = 0
        for segment in segments {
            let siblingCenter = editorStart + segment.editorDuration / 2
            if segment.id != segmentID,
               (editorDelta > 0 ? siblingCenter <= center : siblingCenter < center) {
                insertionIndex += 1
            }
            editorStart += segment.editorDuration
        }
        return insertionIndex
    }

    func remappedEditorTime(_ time: TimeInterval, from previous: RecordingClipTimeline) -> TimeInterval {
        guard time.isFinite, !previous.segments.isEmpty else { return time }
        if time >= previous.duration {
            return duration + time - previous.duration
        }
        guard let location = previous.location(at: time) else { return time }
        if let segment = segments.first(where: { $0.id == location.segmentID }),
           let range = editorRange(for: segment.id) {
            if location.sourceTime < segment.sourceStart || location.sourceTime >= segment.sourceEnd {
                let owner = previous.segments[location.segmentIndex]
                let previousIDs = Set(previous.segments.map(\.id))
                if let continuation = segments.first(where: {
                    !previousIDs.contains($0.id)
                        && $0.sourceStart >= owner.sourceStart
                        && $0.sourceEnd <= owner.sourceEnd
                        && $0.sourceStart <= location.sourceTime
                        && location.sourceTime < $0.sourceEnd
                }), let mapped = editorTime(forSourceTime: location.sourceTime, in: continuation.id) {
                    return mapped
                }
            }
            let sourceOffset = min(max(location.sourceTime - segment.sourceStart, 0), segment.duration)
            return range.lowerBound + sourceOffset / segment.speed
        }
        for segment in previous.segments.dropFirst(location.segmentIndex + 1) {
            if let range = editorRange(for: segment.id) { return range.lowerBound }
        }
        let previousIDs = Set(previous.segments.map(\.id))
        if !segments.contains(where: { previousIDs.contains($0.id) }),
           let mapped = editorTime(forSourceTime: location.sourceTime) {
            return mapped
        }
        return duration
    }
}

nonisolated struct RecordingClipSequenceRipple {
    var audioClips: [RecordingAudioClip]
    var zoomCues: [ZoomCue]

    func applying(from previous: RecordingClipTimeline, to next: RecordingClipTimeline) -> Self {
        var result = self
        result.audioClips = audioClips.map { clip in
            var clip = clip
            clip.start = next.remappedEditorTime(clip.start, from: previous)
            return clip
        }
        let previousIDs = previous.segments.map(\.id)
        let nextIDs = next.segments.map(\.id)
        let survivingIDs = Set(previousIDs).intersection(nextIDs)
        guard previousIDs.filter({ survivingIDs.contains($0) })
            != nextIDs.filter({ survivingIDs.contains($0) }) else { return result }
        result.zoomCues = zoomCues.flatMap { cue in
            let slices = next.slices(overlapping: cue.start, sourceEnd: cue.end)
            guard zip(slices, slices.dropFirst()).contains(where: {
                $1.editorStart - $0.editorEnd > 0.000_001
            }) else { return [cue] }
            let ranges = RecordingClipTimeline.mergedRanges(slices.map { $0.sourceStart...$0.sourceEnd })
            let cuts = Set(slices.flatMap { [$0.sourceStart, $0.sourceEnd] }).sorted()
            var fragments: [ZoomCue] = []
            for (start, end) in zip(cuts, cuts.dropFirst()) where end > start {
                guard ranges.contains(where: { $0.lowerBound <= start && end <= $0.upperBound }) else { continue }
                var fragment = cue
                fragment.id = fragments.isEmpty ? cue.id : UUID()
                fragment.start = start
                fragment.end = end
                fragments.append(fragment)
            }
            return fragments.isEmpty ? [cue] : fragments
        }
        return result
    }
}
