import AppKit
import CoreGraphics

@MainActor
final class CaptureShelfActiveScreenFollower {
    static let shared = CaptureShelfActiveScreenFollower()

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var pointerDisplayID: CGDirectDisplayID?

    private init() {}

    func start() {
        guard globalMonitor == nil, localMonitor == nil else { return }
        pointerDisplayID = nil
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { _ in
            MainActor.assumeIsolated { CaptureShelfActiveScreenFollower.shared.pointerMoved() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { event in
            CaptureShelfActiveScreenFollower.shared.pointerMoved()
            return event
        }
        AppLog.event("quick_access", "quick_access_move_to_active_screen", fields: ["enabled": String(UpshotPreferences.previewMoveToActiveScreen), "outcome": "started"])
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        pointerDisplayID = nil
    }

    private func pointerMoved() {
        guard UpshotPreferences.previewMoveToActiveScreen else { return }
        let pointer = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) }),
              let displayID = ActiveDisplayResolver.displayID(for: screen),
              displayID != pointerDisplayID else { return }
        pointerDisplayID = displayID
        CaptureShelfPresenter.shared.setTargetDisplay(displayID)
        AppLog.event("quick_access", "quick_access_move_to_active_screen", fields: ["display": String(displayID), "outcome": "moved"])
    }
}
