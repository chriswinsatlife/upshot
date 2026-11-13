
import AppKit
import CoreGraphics

nonisolated struct CaptureSource: Codable, Sendable, Hashable {
    var bundleIdentifier: String?
    var appName: String
    var windowTitle: String?

    var appKey: String { bundleIdentifier ?? appName }
}

@MainActor
final class CaptureSourceProbe {
    enum Target {
        case display(CGDirectDisplayID?)
        case window
        case area
    }

    private struct Window {
        let pid: pid_t
        let ownerName: String
        let title: String?
        let bounds: CGRect
    }

    private let windows: [Window]
    private let frontmostPID: pid_t?
    private var pressedAt: CGPoint?
    private var releasedAt: CGPoint?
    private var monitor: Any?
    private(set) var selectionModifiers: NSEvent.ModifierFlags = []
    private(set) var selectedWindowBounds: CGRect?

    init(tracksPointer: Bool) {
        windows = Self.onScreenWindows()
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        frontmostPID = frontmost == getpid() ? nil : frontmost
        guard tracksPointer else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let location = Self.quartzPoint(NSEvent.mouseLocation)
            let isPress = event.type == .leftMouseDown
            MainActor.assumeIsolated {
                guard let self else { return }
                if isPress {
                    self.pressedAt = location
                } else {
                    self.releasedAt = location
                    self.selectionModifiers = event.modifierFlags
                }
            }
        }
    }

    func finish(_ target: Target) -> CaptureSource? {
        stop()
        let window: Window?
        switch target {
        case .display(let displayID):
            let screen = displayID.map(CGDisplayBounds) ?? .infinite
            let onDisplay = windows.filter { $0.bounds.intersects(screen) }
            window = onDisplay.first { $0.pid == frontmostPID } ?? onDisplay.first
        case .window:
            window = topmostWindow(at: releasedAt ?? Self.quartzPoint(NSEvent.mouseLocation))
        case .area:
            if let pressedAt, let releasedAt {
                let area = CGRect(origin: pressedAt, size: .zero).union(CGRect(origin: releasedAt, size: .zero))
                window = topmostWindow(at: CGPoint(x: area.midX, y: area.midY))
                    ?? windows.max { $0.bounds.intersection(area).area < $1.bounds.intersection(area).area }
                        .flatMap { $0.bounds.intersects(area) ? $0 : nil }
            } else {
                window = topmostWindow(at: releasedAt ?? Self.quartzPoint(NSEvent.mouseLocation))
            }
        }
        guard let window else { return nil }
        selectedWindowBounds = window.bounds
        let app = NSRunningApplication(processIdentifier: window.pid)
        return CaptureSource(
            bundleIdentifier: app?.bundleIdentifier,
            appName: app?.localizedName ?? window.ownerName,
            windowTitle: window.title
        )
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func topmostWindow(at point: CGPoint) -> Window? {
        windows.first { $0.bounds.contains(point) }
    }

    private static func onScreenWindows() -> [Window] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        let ownPID = getpid()
        let ignoredOwners: Set<String> = ["Window Server", "Dock", "screencapture", "Screenshot", "Control Center"]
        return list.compactMap { info in
            guard (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1 > 0,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, pid != ownPID,
                  let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CaptureRectangleDecoder.decode(boundsDictionary),
                  bounds.width >= 40, bounds.height >= 40 else { return nil }
            let owner = info[kCGWindowOwnerName as String] as? String ?? ""
            guard !ignoredOwners.contains(owner) else { return nil }
            let title = (info[kCGWindowName as String] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return Window(pid: pid, ownerName: owner, title: title?.isEmpty == false ? title : nil, bounds: bounds)
        }
    }

    private nonisolated static func quartzPoint(_ point: NSPoint) -> CGPoint {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: point.x, y: primaryHeight - point.y)
    }
}

private extension CGRect {
    nonisolated var area: CGFloat { isNull ? 0 : width * height }
}
