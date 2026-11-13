
import AppKit
import Foundation

@MainActor
final class RecordingKeystrokeRecorder {
    private struct CapturedKeystroke {
        let uptime: TimeInterval
        let modifiers: [String]
        let key: String
    }

    private struct PauseInterval {
        let start: TimeInterval
        let end: TimeInterval
    }

    private var events: [CapturedKeystroke] = []
    private var pauseStartedUptime: TimeInterval?
    private var pauseIntervals: [PauseInterval] = []
    private var isCapturing = false
    private var capturesTypedKeys = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?

    private var lastModifierFlags: NSEvent.ModifierFlags = []
    private var lastProcessedEventTimes: [Int: TimeInterval] = [:]
    private static let duplicateEventWindow: TimeInterval = 0.05

    func start() {
        stop()
        events = []
        pauseStartedUptime = nil
        pauseIntervals = []
        lastModifierFlags = []
        lastProcessedEventTimes = [:]
        isCapturing = true
        capturesTypedKeys = UpshotPreferences.recordingCapturesTypedKeys
        NSLog("[Upshot] Keystroke capture started typedKeys=%@", String(capturesTypedKeys))

        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
        }
        installEventTap()

        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
    }

    func stop() {
        isCapturing = false
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        eventTap = nil
        runLoopSource = nil
        globalMonitor = nil
        localMonitor = nil
        lastModifierFlags = []
        lastProcessedEventTimes = [:]
    }

    func pause() {
        guard pauseStartedUptime == nil else { return }
        pauseStartedUptime = ProcessInfo.processInfo.systemUptime
    }

    func resume() {
        guard let pauseStartedUptime else { return }
        pauseIntervals.append(PauseInterval(
            start: pauseStartedUptime,
            end: ProcessInfo.processInfo.systemUptime
        ))
        self.pauseStartedUptime = nil
    }

    func finish(sessionStartUptime: TimeInterval, duration: TimeInterval) -> [RecordingKeystrokeEvent] {
        var completedPauses = pauseIntervals
        if let pauseStartedUptime {
            completedPauses.append(PauseInterval(
                start: pauseStartedUptime,
                end: ProcessInfo.processInfo.systemUptime
            ))
        }

        let mapped = events.compactMap { event -> RecordingKeystrokeEvent? in
            let precedingPauseDuration = completedPauses.reduce(0.0) { total, interval in
                guard event.uptime > interval.start else { return total }
                return total + max(0, min(event.uptime, interval.end) - interval.start)
            }
            let time = event.uptime - sessionStartUptime - precedingPauseDuration
            guard time >= 0, time <= duration + 0.5 else { return nil }
            return RecordingKeystrokeEvent(
                time: min(time, duration),
                modifiers: event.modifiers,
                key: event.key
            )
        }

        events = []
        pauseIntervals = []
        pauseStartedUptime = nil
        return mapped
    }


    private func installEventTap() {
        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        let callback: CGEventTapCallBack = { _, type, cgEvent, refcon in
            guard let refcon else { return Unmanaged.passUnretained(cgEvent) }

            let recorder = Unmanaged<RecordingKeystrokeRecorder>
                .fromOpaque(refcon)
                .takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated {
                    if let tap = recorder.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                }
                return Unmanaged.passUnretained(cgEvent)
            }

            if let nsEvent = NSEvent(cgEvent: cgEvent) {
                DispatchQueue.main.async {
                    recorder.handle(nsEvent)
                }
            }
            return Unmanaged.passUnretained(cgEvent)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        ) else {
            NSLog("[Upshot] Keystroke event tap unavailable; using NSEvent monitors only.")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
    }

    private func handle(_ event: NSEvent) {
        guard isCapturing else { return }
        let uptime = event.timestamp > 0 ? event.timestamp : ProcessInfo.processInfo.systemUptime

        let dedupeKey = (Int(event.type.rawValue) << 16) | Int(event.keyCode)
        if let lastTime = lastProcessedEventTimes[dedupeKey],
           uptime - lastTime < Self.duplicateEventWindow {
            return
        }
        lastProcessedEventTimes[dedupeKey] = uptime

        switch event.type {
        case .flagsChanged:
            let currentFlags = event.modifierFlags.intersection(Self.trackedModifierMask)
            let changedFlags = currentFlags.symmetricDifference(lastModifierFlags)
            lastModifierFlags = currentFlags

            if changedFlags.contains(.capsLock) {
                record(modifiers: [], key: "⇪", uptime: uptime)
            }

        case .keyDown:
            guard !event.isARepeat else { return }

            let modifiers = Self.effectiveModifiers(
                rawFlags: event.modifierFlags,
                triggerKeyCode: event.keyCode
            )

            if let special = Self.specialKeyLabel(for: event.keyCode) {
                record(
                    modifiers: Self.modifierSymbols(for: modifiers),
                    key: special,
                    uptime: uptime
                )
                return
            }

            let chordModifiers = modifiers.subtracting(.shift)
            guard Self.capturesCharacter(modifiers: chordModifiers, capturesTypedKeys: capturesTypedKeys),
                  let raw = event.charactersIgnoringModifiers,
                  let first = raw.first,
                  !first.isWhitespace,
                  !first.isNewline else {
                return
            }
            record(
                modifiers: Self.modifierSymbols(for: modifiers),
                key: String(first).uppercased(),
                uptime: uptime
            )

        default:
            break
        }
    }

    private func record(modifiers: [String], key: String, uptime: TimeInterval) {
        guard pauseStartedUptime == nil else { return }
        events.append(CapturedKeystroke(uptime: uptime, modifiers: modifiers, key: key))
        if events.count > 4_000 {
            events.removeFirst(events.count - 4_000)
        }
    }


    static func capturesCharacter(modifiers: NSEvent.ModifierFlags, capturesTypedKeys: Bool) -> Bool {
        capturesTypedKeys || !modifiers.subtracting(.shift).isEmpty
    }

    private static let trackedModifierMask: NSEvent.ModifierFlags = [
        .command, .shift, .option, .control, .function, .capsLock
    ]

    private static let displayModifierMask: NSEvent.ModifierFlags = [
        .command, .shift, .option, .control, .function
    ]

    private static let implicitFunctionKeyCodes: Set<UInt16> = [
        123, 124, 125, 126,
        115, 116, 117, 119, 121,
        96, 97, 98, 99, 100, 101, 103, 105, 106, 107,
        109, 111, 113, 118, 120, 122, 64, 79, 80
    ]

    static func effectiveModifiers(
        rawFlags: NSEvent.ModifierFlags,
        triggerKeyCode: UInt16
    ) -> NSEvent.ModifierFlags {
        var modifiers = rawFlags.intersection(displayModifierMask)
        if implicitFunctionKeyCodes.contains(triggerKeyCode) {
            modifiers.remove(.function)
        }
        return modifiers
    }

    static func modifierSymbols(for modifiers: NSEvent.ModifierFlags) -> [String] {
        var symbols: [String] = []
        if modifiers.contains(.control) { symbols.append("\u{2303}") }
        if modifiers.contains(.option) { symbols.append("\u{2325}") }
        if modifiers.contains(.shift) { symbols.append("\u{21E7}") }
        if modifiers.contains(.command) { symbols.append("\u{2318}") }
        if modifiers.contains(.function) { symbols.append("fn") }
        return symbols
    }

    static func specialKeyLabel(for keyCode: UInt16) -> String? {
        switch keyCode {
        case 36: return "\u{23CE}"
        case 48: return "\u{21E5}"
        case 49: return "space"
        case 51: return "\u{232B}"
        case 53: return "esc"
        case 71: return "clear"
        case 76: return "\u{2305}"
        case 115: return "\u{2196}"
        case 116: return "\u{21DE}"
        case 117: return "\u{2326}"
        case 119: return "\u{2198}"
        case 121: return "\u{21DF}"
        case 123: return "\u{2190}"
        case 124: return "\u{2192}"
        case 125: return "\u{2193}"
        case 126: return "\u{2191}"
        case 122: return "F1"
        case 120: return "F2"
        case 99: return "F3"
        case 118: return "F4"
        case 96: return "F5"
        case 97: return "F6"
        case 98: return "F7"
        case 100: return "F8"
        case 101: return "F9"
        case 109: return "F10"
        case 103: return "F11"
        case 111: return "F12"
        case 105: return "F13"
        case 107: return "F14"
        case 113: return "F15"
        case 106: return "F16"
        case 64: return "F17"
        case 79: return "F18"
        case 80: return "F19"
        default: return nil
        }
    }
}
