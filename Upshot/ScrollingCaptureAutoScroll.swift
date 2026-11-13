import AppKit

nonisolated struct ScrollingCaptureWindow: Sendable {
    let windowID: CGWindowID
    let processID: pid_t
    let frame: CGRect
    let layer: Int
    let isOnScreen: Bool
    let opacity: Double
}

@MainActor
final class ScrollingCaptureAutoScroll {
    nonisolated enum Failure: LocalizedError {
        case unavailable
        case closed
        case moved
        case obscured
        case processChanged
        case coveredByControls
        case eventUnavailable

        var errorDescription: String? {
            switch self {
            case .unavailable: "No target window was found for Auto-Scroll."
            case .closed: "The Auto-Scroll target window is no longer on screen."
            case .moved: "The Auto-Scroll target window moved away from the selected area."
            case .obscured: "Another window covers the Auto-Scroll target."
            case .processChanged: "The Auto-Scroll target application changed."
            case .coveredByControls: "The controls cover the Auto-Scroll target."
            case .eventUnavailable: "The Auto-Scroll event could not be created."
            }
        }
    }

    let windowID: CGWindowID?
    private let processID: pid_t?
    private let windows: @MainActor () -> [ScrollingCaptureWindow]
    private let postEvent: @MainActor (CGPoint, Int32, pid_t) throws -> Void

    init(rect: CGRect,
         windows: @escaping @MainActor () -> [ScrollingCaptureWindow] = ScrollingCaptureAutoScroll.onScreenWindows,
         postEvent: @escaping @MainActor (CGPoint, Int32, pid_t) throws -> Void = ScrollingCaptureAutoScroll.postEvent) {
        self.windows = windows
        self.postEvent = postEvent
        let point = CGPoint(x: rect.midX, y: rect.midY)
        let target = windows().first { $0.isOnScreen && $0.opacity > 0 && $0.layer == 0 && $0.frame.contains(point) }
        windowID = target?.windowID
        processID = target?.processID
        NSLog("Scrolling capture auto-scroll target recorded: window=%u process=%d", windowID ?? 0, processID ?? 0)
    }

    func scroll(in rect: CGRect, excluding panelFrame: CGRect) throws {
        guard let windowID, let processID else { throw Failure.unavailable }
        let points = [CGPoint(x: rect.midX, y: rect.midY), CGPoint(x: rect.midX, y: rect.maxY - rect.height / 5),
                      CGPoint(x: rect.minX + rect.width / 5, y: rect.midY), CGPoint(x: rect.maxX - rect.width / 5, y: rect.midY)]
        guard let point = points.first(where: { !panelFrame.insetBy(dx: -4, dy: -4).contains($0) }) else {
            throw Failure.coveredByControls
        }
        let currentWindows = windows()
        guard let target = currentWindows.first(where: { $0.windowID == windowID && $0.isOnScreen && $0.opacity > 0 }) else {
            throw Failure.closed
        }
        guard target.processID == processID else { throw Failure.processChanged }
        guard target.frame.contains(point) else { throw Failure.moved }
        guard let frontmost = currentWindows.first(where: { $0.isOnScreen && $0.opacity > 0 && $0.frame.contains(point) }),
              frontmost.windowID == windowID, frontmost.processID == processID else { throw Failure.obscured }
        try postEvent(point, -Int32(max(1, min(200, rect.height / 4))), processID)
    }

    private static func postEvent(at point: CGPoint, delta: Int32, processID: pid_t) throws {
        guard let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1,
                                  wheel1: delta, wheel2: 0, wheel3: 0) else { throw Failure.eventUnavailable }
        event.location = ActiveDisplayResolver.quartzPoint(fromAppKit: point)
        event.postToPid(processID)
    }

    private static func onScreenWindows() -> [ScrollingCaptureWindow] {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let windowID = window[kCGWindowNumber as String] as? CGWindowID,
                  let processID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return ScrollingCaptureWindow(windowID: windowID, processID: processID,
                                          frame: ActiveDisplayResolver.appKitRect(fromQuartz: frame),
                                          layer: window[kCGWindowLayer as String] as? Int ?? 0,
                                          isOnScreen: window[kCGWindowIsOnscreen as String] as? Bool ?? true,
                                          opacity: window[kCGWindowAlpha as String] as? Double ?? 1)
        }
    }
}
