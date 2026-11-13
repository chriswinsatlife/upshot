import AppKit
import CoreGraphics
import Foundation

@MainActor
final class DesktopIconVisibilityService {
    static let shared = DesktopIconVisibilityService()

    private var covers: [NSWindow] = []
    private var captureLeases: Set<UUID> = []
    private(set) var manuallyHidden = false
    private var screenObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?

    var coverWindowIDs: Set<CGWindowID> {
        Set(covers.map { CGWindowID($0.windowNumber) })
    }

    private init() {
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfHidden() }
        }
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshIfHidden() }
        }
    }

    static func toggleDesktopIcons() throws {
        try shared.setManuallyHidden(!shared.manuallyHidden)
    }

    func beginCapture() async throws -> UUID? {
        guard UpshotPreferences.screenshotHideDesktopIcons else { return nil }
        let token = UUID()
        if covers.isEmpty { try installCovers() }
        captureLeases.insert(token)
        do {
            try await Task.sleep(for: .milliseconds(100))
            try Task.checkCancellation()
        } catch {
            endCapture(token)
            throw error
        }
        NSLog("Screenshot output: desktop icons hidden for capture")
        return token
    }

    func endCapture(_ token: UUID?) {
        guard let token, captureLeases.remove(token) != nil else { return }
        if captureLeases.isEmpty && !manuallyHidden { removeCovers() }
        NSLog("Screenshot output: desktop icon capture lease released hidden=%d", !covers.isEmpty)
    }

    private func setManuallyHidden(_ hidden: Bool) throws {
        if hidden && covers.isEmpty { try installCovers() }
        manuallyHidden = hidden
        if !hidden && captureLeases.isEmpty { removeCovers() }
        NSLog("Screenshot output: desktop icons toggled hidden=%d", !covers.isEmpty)
    }

    private func installCovers() throws {
        var replacements: [NSWindow] = []
        do {
            for screen in NSScreen.screens {
                guard let wallpaperURL = NSWorkspace.shared.desktopImageURL(for: screen),
                      let wallpaper = NSImage(contentsOf: wallpaperURL),
                      let pixels = wallpaper.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    throw ScreenshotWindowBackgroundError.wallpaperUnavailable
                }
                let window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
                window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
                window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
                window.isReleasedWhenClosed = false
                window.ignoresMouseEvents = true
                window.hidesOnDeactivate = false
                window.sharingType = .readOnly
                window.backgroundColor = .black
                let view = NSView(frame: CGRect(origin: .zero, size: screen.frame.size))
                view.wantsLayer = true
                view.layer?.contents = pixels
                view.layer?.contentsGravity = .resizeAspectFill
                view.layer?.contentsScale = screen.backingScaleFactor
                view.layer?.masksToBounds = true
                window.contentView = view
                replacements.append(window)
            }
        } catch {
            replacements.forEach { $0.close() }
            throw error
        }
        replacements.forEach { $0.orderFrontRegardless() }
        removeCovers()
        covers = replacements
    }

    private func removeCovers() {
        covers.forEach { $0.orderOut(nil); $0.close() }
        covers.removeAll()
    }

    private func refreshIfHidden() {
        guard manuallyHidden || !captureLeases.isEmpty else { return }
        do {
            try installCovers()
        } catch {
            NSLog("Screenshot output: desktop icon wallpaper refresh failed error=%@", error.localizedDescription)
        }
    }
}
