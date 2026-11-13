
import AppKit
import ScreenCaptureKit
import SwiftUI

@MainActor
@Observable
final class RecordingSourceTargetPresenter {
    static let shared = RecordingSourceTargetPresenter()

    enum Mode: Equatable {
        case display
        case window
    }

    struct Target: Equatable {
        enum Source: Equatable {
            case display(CGDirectDisplayID)
            case window(CGWindowID)
        }

        let source: Source
        let frame: CGRect
        let title: String
        let detail: String
        let icon: NSImage?
    }

    private(set) var mode: Mode?
    private(set) var target: Target?

    @ObservationIgnored private var panels: [NSPanel] = []
    @ObservationIgnored private var windowStack: [(id: CGWindowID, frame: CGRect)] = []
    @ObservationIgnored private var keyMonitors: [Any] = []

    private init() {}

    var isActive: Bool { mode != nil }
    func toggle(_ mode: Mode) {
        if self.mode == mode {
            cancel()
        } else {
            begin(mode)
        }
    }

    func begin(_ mode: Mode) {
        RecordingAreaSelectionPresenter.shared.cancel()
        self.mode = mode
        if mode == .window {
            snapshotWindowStack()
        }
        showPanels()
        installKeyMonitors()
        updateTarget(at: NSEvent.mouseLocation)
        Task {
            await RecordingSourceCatalog.shared.refresh()
            guard self.mode == mode else { return }
            if mode == .window {
                snapshotWindowStack()
            }
            updateTarget(at: NSEvent.mouseLocation)
        }
    }

    func cancel() {
        mode = nil
        target = nil
        windowStack = []
        removeKeyMonitors()
        for panel in panels {
            panel.orderOut(nil)
        }
        panels = []
    }

    fileprivate func updateTarget(at point: CGPoint) {
        let next: Target? = switch mode {
        case .display: displayTarget(at: point)
        case .window: windowTarget(at: point)
        case nil: nil
        }
        guard next != target else { return }
        withAnimation(.easeOut(duration: 0.12)) {
            target = next
        }
    }

    fileprivate func commit(at point: CGPoint) {
        updateTarget(at: point)
        guard let target else { return }
        let sources = RecordingSourceCatalog.shared

        switch target.source {
        case let .display(displayID):
            guard let display = sources.displays.first(where: { $0.displayID == displayID }) else { return }
            cancel()
            RecordingBarPresenter.shared.closeTeleprompter()
            CaptureCoordinator.shared.recordFullscreen(display)
        case let .window(windowID):
            guard let window = sources.windows.first(where: { $0.windowID == windowID }) else { return }
            cancel()
            RecordingBarPresenter.shared.closeTeleprompter()
            CaptureCoordinator.shared.recordWindow(window)
        }
    }

    private func displayTarget(at point: CGPoint) -> Target? {
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(point, $0.frame, false) }),
              let displayID = ActiveDisplayResolver.displayID(for: screen),
              RecordingSourceCatalog.shared.displays.contains(where: { $0.displayID == displayID }) else {
            return nil
        }

        let scale = screen.backingScaleFactor
        let size = "\(Int(screen.frame.width * scale)) × \(Int(screen.frame.height * scale))"
        let fps = screen.maximumFramesPerSecond
        return Target(
            source: .display(displayID),
            frame: screen.frame,
            title: screen.localizedName,
            detail: fps > 0 ? "\(size) · \(fps) FPS" : size,
            icon: nil
        )
    }

    private func windowTarget(at point: CGPoint) -> Target? {
        guard let hit = windowStack.first(where: { $0.frame.contains(point) }),
              let window = RecordingSourceCatalog.shared.windows.first(where: { $0.windowID == hit.id }) else {
            return nil
        }

        let app = window.owningApplication
        let appName = app?.applicationName ?? "Window"
        let title = window.title.flatMap { $0.isEmpty ? nil : $0 } ?? appName
        let scale = NSScreen.screens
            .first { NSMouseInRect(CGPoint(x: hit.frame.midX, y: hit.frame.midY), $0.frame, false) }?
            .backingScaleFactor ?? 2
        let size = "\(Int(hit.frame.width * scale)) × \(Int(hit.frame.height * scale))"
        let icon = app.flatMap { NSRunningApplication(processIdentifier: $0.processID)?.icon }

        return Target(
            source: .window(hit.id),
            frame: hit.frame,
            title: title,
            detail: title == appName ? size : "\(appName) · \(size)",
            icon: icon
        )
    }

    private func snapshotWindowStack() {
        let recordable = Set(RecordingSourceCatalog.shared.windows.map(\.windowID))
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let ownPID = ProcessInfo.processInfo.processIdentifier

        windowStack = info.compactMap { entry in
            guard let number = entry[kCGWindowNumber as String] as? NSNumber,
                  (entry[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CaptureRectangleDecoder.decode(boundsDict) else {
                return nil
            }
            let id = CGWindowID(number.uint32Value)
            let pid = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
            if pid == ownPID && !recordable.contains(id) { return nil }
            if (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue == 0 { return nil }
            return (id, CGRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height))
        }
    }
    private func installKeyMonitors() {
        guard keyMonitors.isEmpty else { return }
        let isEscape: (NSEvent) -> Bool = { $0.keyCode == 53 }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard isEscape(event), let self, self.isActive else { return event }
            self.cancel()
            return nil
        }) {
            keyMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard isEscape(event) else { return }
            MainActor.assumeIsolated { self?.cancel() }
        }) {
            keyMonitors.append(global)
        }
    }

    private func removeKeyMonitors() {
        for monitor in keyMonitors {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitors = []
    }

    private func showPanels() {
        guard panels.isEmpty else { return }
        panels = NSScreen.screens.map(makePanel(for:))
        for panel in panels {
            panel.orderFrontRegardless()
        }
    }

    private func makePanel(for screen: NSScreen) -> NSPanel {
        let panel = RecordingSourceTargetPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true
        panel.ignoresMouseEvents = false
        panel.setFrame(screen.frame, display: false)

        let sheet = RecordingSourceTargetSheetView(frame: CGRect(origin: .zero, size: screen.frame.size))
        sheet.autoresizingMask = [.width, .height]

        let hostingView = NSHostingView(rootView: RecordingSourceTargetOverlay(screenFrame: screen.frame))
        hostingView.frame = sheet.bounds
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        sheet.addSubview(hostingView)

        panel.contentView = sheet
        return panel
    }
}

private final class RecordingSourceTargetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
private final class RecordingSourceTargetSheetView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(
            NSTrackingArea(
                rect: .zero,
                options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
                owner: self
            )
        )
    }

    override func mouseEntered(with event: NSEvent) {
        RecordingSourceTargetPresenter.shared.updateTarget(at: NSEvent.mouseLocation)
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.arrow.set()
        RecordingSourceTargetPresenter.shared.updateTarget(at: NSEvent.mouseLocation)
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        RecordingSourceTargetPresenter.shared.commit(at: NSEvent.mouseLocation)
    }

    override func rightMouseDown(with event: NSEvent) {
        RecordingSourceTargetPresenter.shared.cancel()
    }
}

private struct RecordingSourceTargetOverlay: View {
    let screenFrame: CGRect

    @State private var presenter = RecordingSourceTargetPresenter.shared

    var body: some View {
        let target = presenter.target
        let local = target.flatMap { localRect(for: $0.frame) }
        let shape = RoundedRectangle(cornerRadius: target.map(highlightRadius(for:)) ?? 0, style: .continuous)

        ZStack(alignment: .topLeading) {
            Color(nsColor: RecordingAreaHighlightView.screenDimmingColor)
                .mask {
                    Rectangle()
                        .overlay(alignment: .topLeading) {
                            if let local {
                                shape
                                    .frame(width: local.width, height: local.height)
                                    .offset(x: local.minX, y: local.minY)
                                    .blendMode(.destinationOut)
                            }
                        }
                        .compositingGroup()
                }

            if let target, let local {
                shape
                    .strokeBorder(Palette.highlight, lineWidth: 2)
                    .frame(width: local.width, height: local.height)
                    .offset(x: local.minX, y: local.minY)

                if ownsCard(for: target) {
                    let visible = local.intersection(CGRect(origin: .zero, size: screenFrame.size))
                    RecordingSourceTargetCard(target: target)
                        .position(x: visible.midX, y: visible.midY)
                        .transition(.opacity)
                }
            }
        }
        .frame(width: screenFrame.width, height: screenFrame.height, alignment: .topLeading)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func highlightRadius(for target: RecordingSourceTargetPresenter.Target) -> CGFloat {
        if case .display = target.source { return 0 }
        return Radius.panel
    }

    private func localRect(for frame: CGRect) -> CGRect? {
        guard frame.intersects(screenFrame) else { return nil }
        return CGRect(
            x: frame.minX - screenFrame.minX,
            y: screenFrame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func ownsCard(for target: RecordingSourceTargetPresenter.Target) -> Bool {
        if UpshotStorage.isRenderingStates { return true }
        let screens = NSScreen.screens.map(\.frame)
        let owner = screens.max { lhs, rhs in
            area(lhs.intersection(target.frame)) < area(rhs.intersection(target.frame))
        }
        return owner == screenFrame
    }

    private func area(_ rect: CGRect) -> CGFloat {
        rect.isNull ? 0 : rect.width * rect.height
    }
}

private struct RecordingSourceTargetCard: View {
    let target: RecordingSourceTargetPresenter.Target

    private static let maximumHeaderWidth: CGFloat = 360
    private static let iconSide = InterfaceMetrics.flyoutRowHeight - Space.m

    var body: some View {
        InterfaceFlyoutMenu {
            HStack(spacing: Space.ml) {
                icon
                VStack(alignment: .leading, spacing: InterfaceMetrics.rowLabelToDetailSpacing) {
                    Text(target.title)
                        .font(.dsHeadline)
                        .foregroundStyle(Palette.label)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(target.detail)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.secondaryLabel)
                        .lineLimit(1)
                }
            }
            .padding(Space.m)
            .frame(maxWidth: Self.maximumHeaderWidth, alignment: .leading)
            .accessibilityElement(children: .combine)

            InterfaceFlyoutDivider()

            InterfaceFlyoutRow("Start Recording", systemImage: "record.circle") {}
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let image = target.icon {
            Image(nsImage: image)
                .resizable()
                .frame(width: Self.iconSide, height: Self.iconSide)
        } else {
            Image(systemName: target.isDisplay ? "display" : "macwindow")
                .font(.system(size: IconSize.toolbar, weight: .regular))
                .foregroundStyle(Palette.label)
                .frame(width: Self.iconSide, height: Self.iconSide)
        }
    }
}

private extension RecordingSourceTargetPresenter.Target {
    var isDisplay: Bool {
        if case .display = source { return true }
        return false
    }
}

extension RecordingSourceTargetPresenter {
    static func renderOverlay(window: Bool) -> some View {
        precondition(UpshotStorage.isRenderingStates)
        let frame = CGRect(x: 0, y: 0, width: 1000, height: 625)
        shared.mode = window ? .window : .display
        shared.target = Target(source: window ? .window(0) : .display(0),
                               frame: window ? CGRect(x: 100, y: 100, width: 800, height: 450) : frame,
                               title: window ? "Release Overview" : "Display 1",
                               detail: window ? "Upshot · 1600 × 900" : "2000 × 1250 · 60 FPS",
                               icon: window ? NSImage(named: NSImage.applicationIconName) : nil)
        return RecordingSourceTargetOverlay(screenFrame: frame)
    }
}
