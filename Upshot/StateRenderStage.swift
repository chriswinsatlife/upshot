import AppKit
import ImageIO
import ScreenCaptureKit
import SwiftUI

enum StateRenderDisplay {
    static let size = CGSize(width: 1728, height: 1117)
    static let scale: CGFloat = 2
    static var pixelWidth: Int { Int(size.width * scale) }
    static var pixelHeight: Int { Int(size.height * scale) }

    static var screen: NSScreen {
        get throws {
            guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main else {
                throw StateRenderFailure(message: "No display is available for rendering")
            }
            guard screen.frame.width >= size.width, screen.frame.height >= size.height, screen.backingScaleFactor == scale else {
                throw StateRenderFailure(message: "The main display must be at least \(Int(size.width)) by \(Int(size.height)) points at 2x; it is \(Int(screen.frame.width)) by \(Int(screen.frame.height)) at \(screen.backingScaleFactor)x")
            }
            return screen
        }
    }

    static var frame: CGRect {
        get throws {
            let screen = try screen
            return CGRect(x: screen.frame.minX, y: screen.frame.maxY - size.height, width: size.width, height: size.height)
        }
    }

    static var visibleFrame: CGRect {
        get throws {
            let screen = try screen
            let frame = try frame
            let top = screen.frame.maxY - screen.visibleFrame.maxY
            let bottom = max(0, screen.visibleFrame.minY - frame.minY)
            return CGRect(x: frame.minX, y: frame.minY + bottom, width: frame.width, height: frame.height - top - bottom)
        }
    }

    static var notchWidth: CGFloat? {
        guard let screen = try? screen, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return nil }
        return screen.frame.width - left.width - right.width
    }

    static var menuBarHeight: CGFloat {
        guard let screen = try? screen else { return 0 }
        return screen.frame.maxY - screen.visibleFrame.maxY
    }

    static func captureRect(for frame: CGRect, on screen: NSScreen) -> CGRect {
        CGRect(x: frame.minX - screen.frame.minX, y: screen.frame.maxY - frame.maxY, width: frame.width, height: frame.height)
    }
}

enum StateRenderWallpaper {
    static let directory = URL(fileURLWithPath: "/System/Library/ExtensionKit/Extensions/NeptuneOneWallpaper.appex/Contents/Resources", isDirectory: true)
    private static var cache: [String: CGImage] = [:]

    static func url(appearance: String) -> URL {
        directory.appendingPathComponent(appearance == "dark" ? "TahoeDark.heic" : "TahoeLight.heic")
    }

    static func image(appearance: String) throws -> CGImage {
        if let cached = cache[appearance] { return cached }
        let url = url(appearance: appearance)
        let longest = max(StateRenderDisplay.size.width, StateRenderDisplay.size.height) * StateRenderDisplay.scale
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: longest,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else {
            throw StateRenderFailure(message: "The Tahoe wallpaper could not be read from \(url.path)")
        }
        cache[appearance] = image
        return image
    }
}

final class StateRenderWallpaperView: NSView {
    init(image: CGImage) {
        super.init(frame: CGRect(origin: .zero, size: StateRenderDisplay.size))
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resizeAspectFill
        layer?.contentsScale = StateRenderDisplay.scale
        layer?.masksToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

final class StateRenderTitledWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var isKeyWindow: Bool { true }
    override var isMainWindow: Bool { true }
    @objc var hasKeyAppearance: Bool { true }
    @objc var hasMainAppearance: Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func _hasMainAppearance() -> Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
    @objc func _hasActiveAppearanceForStandardWindowButton(_ button: Int) -> Bool { true }
}

final class StateRenderAlertWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    @objc var hasKeyAppearance: Bool { true }
    @objc func _hasKeyAppearance() -> Bool { true }
    @objc func _hasActiveAppearance() -> Bool { true }
    @objc func _hasActiveAppearanceIgnoringKeyFocus() -> Bool { true }
}

@MainActor
final class StateRenderStage {
    let appearance: String
    private(set) var windows: [NSWindow] = []
    private var alerts: [NSAlert] = []

    init(appearance: String) throws {
        self.appearance = appearance
        let frame = try StateRenderDisplay.frame
        let wallpaper = StateRenderWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        wallpaper.contentView = StateRenderWallpaperView(image: try StateRenderWallpaper.image(appearance: appearance))
        configure(wallpaper, level: NSWindow.Level(rawValue: StateRenderer.renderLevel.rawValue - 1))
        wallpaper.isOpaque = true
        wallpaper.setFrame(frame, display: false)
        wallpaper.orderBack(nil)
        windows.append(wallpaper)
    }

    func configure(_ window: NSWindow, level: NSWindow.Level = StateRenderer.renderLevel) {
        window.level = level
        window.isReleasedWhenClosed = false
        window.ignoresMouseEvents = true
        window.animationBehavior = .none
        window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        window.sharingType = .readOnly
        (window as? NSPanel)?.hidesOnDeactivate = false
    }

    func present(_ window: NSWindow) {
        configure(window, level: window.level.rawValue < StateRenderer.desktopLevel ? window.level : StateRenderer.renderLevel)
        if let last = windows.last {
            window.order(.above, relativeTo: last.windowNumber)
        } else {
            window.orderBack(nil)
        }
        windows.append(window)
    }

    func insertBelow(_ window: NSWindow, target: NSWindow) {
        let index = windows.firstIndex { $0 === target } ?? windows.count
        window.order(.above, relativeTo: windows[index - 1].windowNumber)
        windows.insert(window, at: index)
    }

    func tearDown() {
        alerts.removeAll()
        for window in windows.reversed() {
            window.orderOut(nil)
            window.contentViewController = nil
            window.contentView = nil
            window.close()
        }
        windows.removeAll()
    }

    func capture() async throws -> (image: CGImage, level: Int) {
        guard CGPreflightScreenCaptureAccess() else {
            throw StateRenderFailure(message: "Display frames require existing Screen Recording access for the rendering app; the renderer never requests it")
        }
        let screen = try StateRenderDisplay.screen
        let frame = try StateRenderDisplay.frame
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw StateRenderFailure(message: "The render display is not available to ScreenCaptureKit")
        }
        let numbers = windows.map { CGWindowID($0.windowNumber) }
        let included = numbers.compactMap { number in content.windows.first { $0.windowID == number } }
        guard included.count == numbers.count else {
            throw StateRenderFailure(message: "ScreenCaptureKit listed \(included.count) of \(numbers.count) render windows")
        }
        for window in included where !window.isOnScreen {
            throw StateRenderFailure(message: "Render window \(window.windowID) is not ordered in at the window server, so it would be missing from the frame")
        }
        for window in included where window.windowLayer >= StateRenderer.desktopLevel {
            throw StateRenderFailure(message: "Render window \(window.windowID) is at window-server layer \(window.windowLayer), not below the desktop layer \(StateRenderer.desktopLevel)")
        }
        let level = included.map(\.windowLayer).max() ?? Int.min
        let filter = SCContentFilter(display: display, including: included)
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = StateRenderDisplay.captureRect(for: frame, on: screen)
        configuration.width = StateRenderDisplay.pixelWidth
        configuration.height = StateRenderDisplay.pixelHeight
        configuration.showsCursor = false
        configuration.ignoreShadowsDisplay = false
        configuration.captureResolution = .best
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        guard image.width == StateRenderDisplay.pixelWidth, image.height == StateRenderDisplay.pixelHeight else {
            throw StateRenderFailure(message: "ScreenCaptureKit returned \(image.width) by \(image.height) pixels")
        }
        return (image, level)
    }
}

enum StateRenderDesktop {
    static var image: CGImage?
    static let recordingRect = CGRect(x: 304, y: 244, width: 1120, height: 630)
    private static var fixtureWindow: CGImage?
    private static let fixtureWindowFraction = CGRect(x: 80.0 / 1280, y: 70.0 / 800, width: 1120.0 / 1280, height: 660.0 / 800)
    private static let fixtureWindowCornerRadius: CGFloat = 16

    static func install(fixtureImage: NSImage) throws {
        guard let source = fixtureImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw StateRenderFailure(message: "The fixture desktop image could not be decoded")
        }
        let crop = CGRect(x: fixtureWindowFraction.minX * CGFloat(source.width), y: fixtureWindowFraction.minY * CGFloat(source.height),
                          width: fixtureWindowFraction.width * CGFloat(source.width), height: fixtureWindowFraction.height * CGFloat(source.height)).integral
        guard let window = source.cropping(to: crop) else { throw StateRenderFailure(message: "The fixture window could not be cropped") }
        fixtureWindow = window
    }

    static func prepare(appearance: String) throws {
        guard let window = fixtureWindow,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: StateRenderDisplay.pixelWidth, height: StateRenderDisplay.pixelHeight,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StateRenderFailure(message: "The fixture desktop image could not be created")
        }
        let scale = StateRenderDisplay.scale
        let target = CGSize(width: StateRenderDisplay.pixelWidth, height: StateRenderDisplay.pixelHeight)
        let wallpaper = try StateRenderWallpaper.image(appearance: appearance)
        let ratio = max(target.width / CGFloat(wallpaper.width), target.height / CGFloat(wallpaper.height))
        let wallpaperSize = CGSize(width: CGFloat(wallpaper.width) * ratio, height: CGFloat(wallpaper.height) * ratio)
        context.interpolationQuality = .high
        context.draw(wallpaper, in: CGRect(x: (target.width - wallpaperSize.width) / 2, y: (target.height - wallpaperSize.height) / 2,
                                           width: wallpaperSize.width, height: wallpaperSize.height))
        let windowSize = CGSize(width: 1120 * scale, height: 660 * scale)
        let windowRect = CGRect(x: (target.width - windowSize.width) / 2, y: (target.height - windowSize.height) / 2 - 40 * scale,
                                width: windowSize.width, height: windowSize.height)
        let path = CGPath(roundedRect: windowRect, cornerWidth: fixtureWindowCornerRadius * scale, cornerHeight: fixtureWindowCornerRadius * scale, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 30 * scale, color: NSColor.black.withAlphaComponent(0.4).cgColor)
        context.addPath(path)
        context.setFillColor(NSColor.white.cgColor)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(path)
        context.clip()
        context.draw(window, in: windowRect)
        context.restoreGState()
        image = context.makeImage()
    }

    static func view() throws -> some View {
        guard let image else { throw StateRenderFailure(message: "The fixture desktop image is unavailable") }
        return Image(decorative: image, scale: StateRenderDisplay.scale)
            .resizable()
            .frame(width: StateRenderDisplay.size.width, height: StateRenderDisplay.size.height)
    }

    static func recordingAreaBackdrop() throws -> AnyView {
        AnyView(try view().overlay {
            StateRenderAppKitView {
                RecordingAreaSelectionSheet(displayID: 0, screenFrame: CGRect(origin: .zero, size: StateRenderDisplay.size), scale: StateRenderDisplay.scale)
            }
        })
    }
}

extension StateRenderStage {
    static func rootView(_ view: AnyView) -> AnyView {
        AnyView(view
            .defaultAppStorage(UpshotStorage.defaults)
            .transaction { $0.disablesAnimations = true })
    }

    @discardableResult
    func addWindow(_ kind: StateRenderAppWindow, view: AnyView) -> NSWindow {
        let window = StateRenderTitledWindow(contentRect: CGRect(origin: .zero, size: kind.contentSize),
                                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                             backing: .buffered, defer: false)
        configure(window)
        window.title = kind.title
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.toolbarStyle = kind == .settings ? .automatic : .unified
        window.hasShadow = true
        let controller = NSHostingController(rootView: Self.rootView(view))
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(kind.contentSize)
        let toolbarHeight = window.frame.height - window.contentLayoutRect.height
        window.setContentSize(CGSize(width: kind.contentSize.width, height: kind.contentSize.height + toolbarHeight))
        window.center()
        present(window)
        return window
    }

    @discardableResult
    func addPanel(_ panel: StateRenderPanel, view: AnyView) throws -> NSWindow {
        let host = NSHostingView(rootView: Self.rootView(view))
        host.sizingOptions = [.intrinsicContentSize]
        host.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        let fitting = host.fittingSize
        host.sizingOptions = []
        let frame = try panel.frame(fitting).integral
        guard frame.width >= 1, frame.height >= 1 else { throw StateRenderFailure(message: "Panel measured \(fitting) and resolved to an empty frame") }
        let window = StateRenderWindow(contentRect: frame, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        configure(window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = panel.hasShadow
        host.frame = CGRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        window.contentView = host
        window.setFrame(frame, display: false)
        present(window)
        return window
    }

    @discardableResult
    func addDisplay(view: AnyView) throws -> NSWindow {
        let frame = try StateRenderDisplay.frame
        let window = StateRenderWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        configure(window)
        window.isOpaque = true
        window.hasShadow = false
        let host = NSHostingView(rootView: Self.rootView(view))
        host.sizingOptions = []
        host.frame = CGRect(origin: .zero, size: frame.size)
        window.contentView = host
        window.setFrame(frame, display: false)
        present(window)
        return window
    }

    static let modalAlertPanelStyleBits: UInt = 68_719_476_736 | 1_048_576

    func addAlert(_ alert: NSAlert, over context: NSWindow?) {
        alert.layout()
        alerts.append(alert)
        let source = alert.window
        let content = source.contentView
        let styleMask = NSWindow.StyleMask(rawValue: source.styleMask.rawValue & ~Self.modalAlertPanelStyleBits)
        let window = StateRenderAlertWindow(contentRect: source.frame, styleMask: styleMask, backing: .buffered, defer: false)
        configure(window)
        window.titleVisibility = source.titleVisibility
        window.titlebarAppearsTransparent = source.titlebarAppearsTransparent
        window.isOpaque = source.isOpaque
        window.backgroundColor = source.backgroundColor
        window.hasShadow = true
        source.contentView = nil
        window.contentView = content
        window.setFrame(source.frame, display: false)
        AppLog.event("rendering", "state_renderer_alert", fields: ["frameView": String(describing: window.contentView?.superview.map { type(of: $0) }),
                                                                   "sourceStyle": String(describing: source.styleMask.rawValue),
                                                                   "style": String(describing: window.styleMask.rawValue)])
        if let context {
            let size = window.frame.size
            let parent = context.frame
            let titlebar = parent.height - context.contentLayoutRect.height
            window.setFrameOrigin(CGPoint(x: (parent.midX - size.width / 2).rounded(),
                                          y: (parent.maxY - titlebar - 24 - size.height).rounded()))
        } else {
            window.center()
        }
        present(window)
    }

    func addPopover(_ view: AnyView, over context: NSWindow, anchor: StateRenderPopoverAnchor) throws {
        guard let anchorView = context.contentView else { throw StateRenderFailure(message: "The popover context has no content view") }
        let host = NSHostingView(rootView: Self.rootView(view))
        host.sizingOptions = [.intrinsicContentSize]
        let fitting = host.fittingSize
        host.sizingOptions = []
        guard fitting.width >= 1, fitting.height >= 1 else { throw StateRenderFailure(message: "Popover content measured \(fitting)") }
        let size = CGSize(width: ceil(fitting.width), height: ceil(fitting.height))
        var anchorRect = anchor.rect(in: anchorView.bounds)
        if anchorView.isFlipped { anchorRect.origin.y = anchorView.bounds.height - anchorRect.maxY }
        let anchorOnScreen = context.convertToScreen(anchorView.convert(anchorRect, to: nil))
        let gap: CGFloat = 6
        var origin: CGPoint
        switch anchor.edge {
        case .minY: origin = CGPoint(x: anchorOnScreen.midX - size.width / 2, y: anchorOnScreen.minY - gap - size.height)
        case .maxY: origin = CGPoint(x: anchorOnScreen.midX - size.width / 2, y: anchorOnScreen.maxY + gap)
        case .minX: origin = CGPoint(x: anchorOnScreen.minX - gap - size.width, y: anchorOnScreen.midY - size.height / 2)
        default: origin = CGPoint(x: anchorOnScreen.maxX + gap, y: anchorOnScreen.midY - size.height / 2)
        }
        let visible = try StateRenderDisplay.visibleFrame.insetBy(dx: 8, dy: 8)
        origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
        origin.y = min(max(origin.y, visible.minY), visible.maxY - size.height)
        let frame = CGRect(origin: origin, size: size).integral
        let glass = NSGlassEffectView(frame: CGRect(origin: .zero, size: frame.size))
        glass.cornerRadius = Self.popoverCornerRadius
        host.frame = glass.bounds
        host.autoresizingMask = [.width, .height]
        glass.contentView = host
        let window = StateRenderWindow(contentRect: frame, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        configure(window)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.contentView = glass
        window.setFrame(frame, display: false)
        present(window)
    }

    static let popoverCornerRadius: CGFloat = 18

    func primaryScrollView() -> NSScrollView? {
        var candidates: [NSScrollView] = []
        func visit(_ view: NSView) {
            if let scroll = view as? NSScrollView, scroll.documentView != nil,
               StateRenderStage.scrollRange(scroll).upperBound - StateRenderStage.scrollRange(scroll).lowerBound > 2, scroll.contentView.bounds.width > 200 {
                candidates.append(scroll)
            }
            view.subviews.forEach(visit)
        }
        for window in windows.dropFirst() { if let view = window.contentView { visit(view) } }
        return candidates.max { $0.contentView.bounds.width * $0.contentView.bounds.height < $1.contentView.bounds.width * $1.contentView.bounds.height }
    }
}

extension StateRenderStage {
    static func scrollRange(_ scroll: NSScrollView) -> ClosedRange<CGFloat> {
        guard let document = scroll.documentView else { return 0...0 }
        let insets = scroll.contentInsets
        let lower = -insets.top
        let upper = max(lower, document.frame.height + insets.bottom - scroll.contentView.bounds.height)
        return lower...upper
    }
}
