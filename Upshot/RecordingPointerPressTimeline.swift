import Foundation

nonisolated struct RecordingPointerPressTimeline {
    private struct Interaction {
        var down: PointerStreamEvent
        var up: PointerStreamEvent?
    }

    private var buttons: [Int: [Interaction]] = [:]
    private var orderedButtons: [Int] = []

    init(samples: [PointerStreamEvent]) {
        for sample in samples {
            let button = sample.button ?? 0
            if sample.kind == .press {
                var group = buttons[button] ?? []
                if let last = group.indices.last, group[last].up == nil {
                    group[last].up = sample
                }
                group.append(Interaction(down: sample))
                buttons[button] = group
            } else if sample.kind == .release,
                      let last = buttons[button]?.indices.last,
                      buttons[button]?[last].up == nil {
                buttons[button]?[last].up = sample
            }
        }
        orderedButtons = buttons.keys.sorted()
    }

    func frame(at time: TimeInterval, bounceDuration: TimeInterval) -> PointerPressFrame? {
        var latest: Interaction?
        var held: Interaction?
        var latestTransition = -Double.infinity
        for button in orderedButtons {
            guard let group = buttons[button] else { continue }
            var low = 0
            var high = group.count
            while low < high {
                let middle = (low + high) / 2
                if group[middle].down.time <= time { low = middle + 1 } else { high = middle }
            }
            guard low > 0 else { continue }
            let interaction = group[low - 1]
            let isPressed = interaction.up.map { time < $0.time } ?? true
            let transition = isPressed ? interaction.down.time : (interaction.up?.time ?? interaction.down.time)
            if transition >= latestTransition {
                latestTransition = transition
                latest = interaction
            }
            if isPressed, held.map({ $0.down.time <= interaction.down.time }) ?? true {
                held = interaction
            }
        }
        guard let interaction = held ?? latest else { return nil }
        let elapsed = max(0, time - interaction.down.time)
        let isPressed = interaction.up.map { time < $0.time } ?? true
        let releaseAge = isPressed ? nil : interaction.up.map { max(0, time - $0.time) }
        guard isPressed || elapsed <= 1.45 || (releaseAge ?? .infinity) <= 1.2 else { return nil }
        return PointerPressFrame(
            location: interaction.down.location,
            progress: min(elapsed / PointerPressEffectStyle.duration, 1),
            elapsed: elapsed,
            isPressed: isPressed,
            releaseLocation: interaction.up?.location,
            releaseAge: releaseAge,
            bounceDuration: bounceDuration,
            holdDuration: interaction.up.map { max(0, $0.time - interaction.down.time) }
        )
    }
}

nonisolated extension PointerPressFrame {
    func magnification(strength: Double) -> Double {
        let strength = strength.isFinite ? min(max(strength, 0), 5) : 0
        let duration = bounceDuration.isFinite ? min(max(bounceDuration, 0.06), 0.5) : 0.23
        if (holdDuration ?? .infinity) > duration {
            if isPressed {
                let progress = min(0.5, elapsed / duration)
                return max(0.72, 1 - sin(progress * .pi) * 0.08 * strength)
            }
            let releaseProgress = max(0, 1 - (releaseAge ?? 0) / (duration * 0.5))
            let compression = 1 - max(0.72, 1 - 0.08 * strength)
            return 1 - compression * releaseProgress
        }
        let progress = min(max(elapsed / duration, 0), 1)
        return max(0.72, 1 - sin(progress * .pi) * 0.08 * strength)
    }
}
