import AppKit

@MainActor
enum AppActivationPolicy {
    fileprivate static var activeWindowCount = 0

    private static var shelfEditorCount = 0

    static func enter(hidePreview: Bool = false) {
        guard !UpshotStorage.isRenderingStates else { return }
        activeWindowCount += 1
        if hidePreview {

            shelfEditorCount += 1
            CaptureShelf.shared.tuck(.editor)
        }
        NSApp.setActivationPolicy(windowPolicy)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func leave(restorePreview: Bool = false) {
        guard !UpshotStorage.isRenderingStates else { return }
        activeWindowCount = max(0, activeWindowCount - 1)
        if restorePreview {
            shelfEditorCount = max(0, shelfEditorCount - 1)
            if shelfEditorCount == 0 {
                CaptureShelf.shared.untuck(.editor)
            }
        }
        guard activeWindowCount == 0 else { return }

        Task { @MainActor in
            guard activeWindowCount == 0 else { return }
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

extension AppActivationPolicy {

    static var windowPolicy: NSApplication.ActivationPolicy {
        UpshotPreferences.hideDockIcon ? .accessory : .regular
    }

    static func dockIconPreferenceDidChange() {
        guard !UpshotStorage.isRenderingStates else { return }
        guard activeWindowCount > 0 else { return }
        NSApp.setActivationPolicy(windowPolicy)
        NSApp.activate(ignoringOtherApps: true)
    }
}

typealias AnnotationEditorActivationPolicy = AppActivationPolicy
