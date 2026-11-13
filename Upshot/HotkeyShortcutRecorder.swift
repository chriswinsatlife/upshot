
import AppKit
import Carbon.HIToolbox
import Observation

@MainActor
@Observable
final class HotkeyShortcutRecorder {
    private(set) var isRecording = false

    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored var onShortcutRecorded: ((HotkeyShortcut) -> Void)?
    @ObservationIgnored var onCancel: (() -> Void)?

    deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func start() {
        stop()
        HotkeyManager.shared.suspendForShortcutRecording()
        isRecording = true

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            return self.handle(event)
        }
    }

    func stop() {
        isRecording = false

        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        HotkeyManager.shared.resumeAfterShortcutRecording()
    }

    func presentRecordingForRendering() {
        precondition(UpshotStorage.isRenderingStates)
        isRecording = true
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }

        if event.keyCode == UInt16(kVK_Escape) {
            cancel()
            return nil
        }

        let modifiers = HotkeyShortcut.Modifiers(from: event.modifierFlags)
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return nil
        }

        finish(with: HotkeyShortcut(modifiers: modifiers, keyCode: Int(event.keyCode)))
        return nil
    }

    private func finish(with shortcut: HotkeyShortcut) {
        stop()
        onShortcutRecorded?(shortcut)
    }

    private func cancel() {
        onCancel?()
        stop()
    }
}
