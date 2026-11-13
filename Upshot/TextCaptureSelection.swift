import AppKit
import ScreenCaptureKit

@MainActor
final class TextCaptureSelection {
    private var panels: [NSPanel] = []
    private var views: [TextCaptureView] = []
    private var continuation: CheckedContinuation<CGImage?, Never>?
    private var windowSelection = false

    func select() async throws -> CGImage? {
        let windows = Self.windowFrames()
        var images: [(NSScreen, CGDirectDisplayID, CGImage)] = []
        for screen in NSScreen.screens {
            guard let displayID = ActiveDisplayResolver.displayID(for: screen) else { continue }
            let image = try await SCScreenshotManager.captureImage(in: CGDisplayBounds(displayID))
            images.append((screen, displayID, image))
        }
        guard !images.isEmpty else { throw CocoaError(.fileReadUnknown) }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            for (screen, displayID, image) in images {
                let panel = TextCapturePanel(
                    contentRect: screen.frame,
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered,
                    defer: false
                )
                panel.level = .screenSaver
                panel.isOpaque = true
                panel.hasShadow = false
                panel.hidesOnDeactivate = false
                panel.acceptsMouseMovedEvents = true
                panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                let view = TextCaptureView(
                    frame: CGRect(origin: .zero, size: screen.frame.size),
                    displayBounds: CGDisplayBounds(displayID),
                    image: image,
                    windowFrames: windows,
                    completion: { [self] in finish($0) },
                    toggleWindowSelection: { [self] in toggleWindowSelection() }
                )
                panel.contentView = view
                panels.append(panel)
                views.append(view)
                panel.orderFrontRegardless()
            }
            if let panel = panels.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? panels.first {
                panel.makeKey()
                panel.makeFirstResponder(panel.contentView)
            }
        }
    }

    private func toggleWindowSelection() {
        windowSelection.toggle()
        for view in views { view.windowSelection = windowSelection }
    }

    private func finish(_ image: CGImage?) {
        guard let continuation else { return }
        self.continuation = nil
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        continuation.resume(returning: image)
    }

    private static func windowFrames() -> [CGRect] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary), !frame.isEmpty else { return nil }
            return frame
        }
    }
}

private final class TextCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class TextCaptureView: NSView {
    private let displayBounds: CGRect
    private let image: CGImage
    private let windowFrames: [CGRect]
    private let completion: (CGImage?) -> Void
    private let toggleWindowSelection: () -> Void
    private var start: CGPoint?
    private var end: CGPoint?
    private var hoveredWindow: CGRect?
    var windowSelection = false {
        didSet { start = nil; end = nil; updateHoveredWindow(); needsDisplay = true }
    }

    init(frame: CGRect, displayBounds: CGRect, image: CGImage, windowFrames: [CGRect], completion: @escaping (CGImage?) -> Void, toggleWindowSelection: @escaping () -> Void) {
        self.displayBounds = displayBounds
        self.image = image
        self.windowFrames = windowFrames
        self.completion = completion
        self.toggleWindowSelection = toggleWindowSelection
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: completion(nil)
        case 49: toggleWindowSelection()
        default: super.keyDown(with: event)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        updateHoveredWindow()
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        if windowSelection {
            updateHoveredWindow()
            if let hoveredWindow { complete(rect: hoveredWindow) }
            return
        }
        start = convert(event.locationInWindow, from: nil)
        end = start
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard !windowSelection else { return }
        end = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard !windowSelection, let start else { return }
        let end = convert(event.locationInWindow, from: nil)
        complete(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)))
    }

    private func complete(rect: CGRect) {
        let rect = rect.intersection(bounds)
        guard rect.width >= 1, rect.height >= 1 else { completion(nil); return }
        let scaleX = CGFloat(image.width) / bounds.width
        let scaleY = CGFloat(image.height) / bounds.height
        let crop = CGRect(x: rect.minX * scaleX, y: (bounds.height - rect.maxY) * scaleY, width: rect.width * scaleX, height: rect.height * scaleY).integral
        completion(image.cropping(to: crop))
    }

    private func updateHoveredWindow() {
        guard windowSelection, let window else { hoveredWindow = nil; needsDisplay = true; return }
        let localPoint = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let screenPoint = CGPoint(x: displayBounds.minX + localPoint.x, y: displayBounds.minY + bounds.height - localPoint.y)
        hoveredWindow = windowFrames.first(where: { $0.contains(screenPoint) }).map {
            CGRect(x: $0.minX - displayBounds.minX, y: bounds.height - ($0.maxY - displayBounds.minY), width: $0.width, height: $0.height).intersection(bounds)
        }
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(image, in: bounds)
        NSColor.black.withAlphaComponent(0.25).setFill()
        bounds.fill()
        let selected: CGRect?
        if windowSelection {
            selected = hoveredWindow
        } else if let start, let end {
            selected = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
        } else {
            selected = nil
        }
        if let selected {
            context.saveGState()
            context.clip(to: selected)
            context.draw(image, in: bounds)
            context.restoreGState()
            NSColor.white.setStroke()
            selected.frame()
        }
    }
}
