import AppKit
import SwiftUI

@Observable
@MainActor
final class RecordingBarPresenter {
    static let shared = RecordingBarPresenter()

    enum Mode: Equatable {
        case picker
        case recording
    }

    private(set) var mode: Mode = .picker
    private(set) var isTeleprompterOpen = false
    private(set) var renderHoveredOutputMode: RecordingOutputMode?

    var barFrameInPanel: CGRect = .zero
    var visibilityToastFrameInPanel: CGRect = .zero
    var areaPillFrameInPanel: CGRect?
    var startFlyoutFrameInPanel: CGRect?

    func containsPanelPoint(_ point: CGPoint) -> Bool {
        if barFrameInPanel.contains(point) { return true }
        if let areaPillFrameInPanel, areaPillFrameInPanel.contains(point) { return true }
        if let startFlyoutFrameInPanel, startFlyoutFrameInPanel.contains(point) { return true }
        return mode == .picker
            && UpshotPreferences.includeAppWindowsInCaptures
            && visibilityToastFrameInPanel.contains(point)
    }

    @ObservationIgnored private var panel: NSPanel?

    private init() {}

    func toggleTeleprompter() {
        withAnimation(BarMetrics.modeChange) { isTeleprompterOpen.toggle() }
        if isTeleprompterOpen { panel?.makeKey() }
    }

    func closeTeleprompter() {
        guard isTeleprompterOpen else { return }
        withAnimation(BarMetrics.modeChange) { isTeleprompterOpen = false }
    }

    func togglePicker() {
        if let panel, panel.isVisible, mode == .picker {
            hide()
        } else {
            showPicker()
        }
    }

    func showPicker() {
        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        Task {
            await RecordingSourceCatalog.shared.refresh()
        }
        RecordingOutputModeCoordinator.shared.clearPendingMode()
        mode = .picker
        panel.level = .floating
        position(panel, displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: false))
        panel.orderFrontRegardless()
        panel.makeKey()
        warmCameraPreviewIfEnabled()
    }

    func showRecording(displayID: CGDirectDisplayID?) {
        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        RecordingSourceTargetPresenter.shared.cancel()
        RecordingAreaSelectionPresenter.shared.cancel()
        if mode != .recording {
            RecordingOutputModeCoordinator.shared.beginSession()
        }

        let isMorphing = panel.isVisible && isPositioned(panel, onDisplayID: displayID)
        if isMorphing {
            withAnimation(BarMetrics.modeChange) {
                mode = .recording
                isTeleprompterOpen = false
            }
        } else {
            mode = .recording
            isTeleprompterOpen = false
            position(panel, displayID: displayID)
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    func hide() {
        if mode == .picker { CaptureCountdownPresenter.shared.cancel() }
        RecordingSourceTargetPresenter.shared.cancel()
        RecordingAreaSelectionPresenter.shared.cancel()
        panel?.orderOut(nil)
        mode = .picker
        isTeleprompterOpen = false
    }

    func reclaimKey() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
    }

    func containsScreenPoint(_ point: CGPoint) -> Bool {
        guard let panel, panel.isVisible else { return false }
        return containsPanelPoint(CGPoint(
            x: point.x - panel.frame.minX,
            y: panel.frame.maxY - point.y
        ))
    }

    var barFrame: CGRect? {
        guard let panel, panel.isVisible, barFrameInPanel != .zero else { return nil }
        return screenFrame(for: barFrameInPanel, in: panel)
    }

    var areaPillFrame: CGRect? {
        guard let panel, panel.isVisible else { return nil }
        let frames = [areaPillFrameInPanel, startFlyoutFrameInPanel].compactMap { $0 }
        guard let first = frames.first else { return nil }
        return screenFrame(for: frames.dropFirst().reduce(first) { $0.union($1) }, in: panel)
    }

    private func screenFrame(for frameInPanel: CGRect, in panel: NSPanel) -> CGRect {
        CGRect(
            x: panel.frame.minX + frameInPanel.minX,
            y: panel.frame.maxY - frameInPanel.maxY,
            width: frameInPanel.width,
            height: frameInPanel.height
        )
    }

    private func isPositioned(_ panel: NSPanel, onDisplayID displayID: CGDirectDisplayID?) -> Bool {
        guard let target = ActiveDisplayResolver.screen(for: displayID) else { return true }
        return target.frame.intersects(panel.frame)
    }

    private func position(_ panel: NSPanel, displayID: CGDirectDisplayID?) {
        let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main
        panel.setFrame(Self.panelFrame(visibleFrame: screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)), display: true)
    }

    static func panelFrame(visibleFrame: CGRect) -> CGRect {
        let size = CGSize(width: BarMetrics.panelWidth, height: BarMetrics.panelHeight)
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 48 - BarMetrics.bottomSlack
        )
        return CGRect(origin: origin, size: size)
    }

    private func warmCameraPreviewIfEnabled() {
        let cameraID = UpshotPreferences.recordingCameraDeviceID
        guard !cameraID.isEmpty else { return }
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        Task {
            await CameraRecordingManager.shared.startPreview(deviceID: cameraID, displayID: displayID)
        }
    }

    private func makePanel() -> NSPanel {
        let size = CGSize(width: BarMetrics.panelWidth, height: BarMetrics.panelHeight)
        let panel = RecordingBarPanel(
            contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isMovableByWindowBackground = true
        panel.acceptsMouseMovedEvents = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        PreviewWindowCaptureExclusion.shared.register(window: panel)

        let hostingView = RecordingBarHostingView(rootView: RecordingBarView())
        hostingView.frame = CGRect(origin: .zero, size: size)
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView
        panel.contentView?.superview?.wantsLayer = true
        panel.contentView?.superview?.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView?.superview?.layer?.isOpaque = false

        self.panel = panel
        return panel
    }
}

private final class RecordingBarPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }

    override func cancelOperation(_ sender: Any?) {
        guard RecordingBarPresenter.shared.mode == .picker else { return }
        if RecordingBarPresenter.shared.isTeleprompterOpen {
            RecordingBarPresenter.shared.closeTeleprompter()
            return
        }
        if RecordingAreaSelectionPresenter.shared.isActive {
            RecordingAreaSelectionPresenter.shared.cancel()
            return
        }
        if RecordingSourceTargetPresenter.shared.isActive {
            RecordingSourceTargetPresenter.shared.cancel()
            return
        }
        RecordingBarPresenter.shared.hide()
        Task { await CameraRecordingManager.shared.stopPreview() }
    }
}

private final class RecordingBarHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard RecordingBarPresenter.shared.containsPanelPoint(convert(point, from: superview)) else {
            return nil
        }
        return super.hitTest(point)
    }
}

struct RecordingBarView: View {
    @State private var presenter = RecordingBarPresenter.shared
    @State private var area = RecordingAreaSelectionPresenter.shared
    @State private var rowWidth: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(UpshotPreferences.includeAppWindowsInCapturesKey)
    private var includeAppWindowsInCaptures = false

    var body: some View {
        bar
            .padding(.bottom, BarMetrics.bottomSlack)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .coordinateSpace(.named(BarCoordinateSpace.panel))
            .onChange(of: includeAppWindowsInCaptures) { _, _ in
                guard !UpshotStorage.isRenderingStates else { return }
                PreviewWindowCaptureExclusion.shared.refreshRegisteredWindows()
                Task { await RecordingSourceCatalog.shared.refresh() }
            }
    }

    private var showsTeleprompter: Bool {
        presenter.mode == .picker && presenter.isTeleprompterOpen
    }

    private var showsAreaControls: Bool {
        presenter.mode == .picker && area.isActive
    }

    private var showsStartFlyout: Bool {
        showsAreaControls && area.selection != nil
    }

    private var accessoryTransition: AnyTransition {
        reduceMotion
            ? .opacity.animation(.easeOut(duration: 0.15))
            : .opacity.combined(with: .offset(x: -Space.l)).animation(.easeOut(duration: 0.18))
    }

    private var bar: some View {
        VStack(spacing: 0) {
            if showsTeleprompter {
                RecordingBarTeleprompter()
                    .frame(width: rowWidth)
                    .transition(.opacity)
                InterfaceFlyoutDivider()
                    .frame(width: rowWidth)
            }

            controlRow
        }
        .padding(InterfaceMetrics.floatingPanelPadding)
        .interfacePanelSurface(.panel)
        .background(alignment: .top) {
            if presenter.mode == .picker && includeAppWindowsInCaptures {
                visibilityToast
                    .padding(.top, presenter.barFrameInPanel.height + BarMetrics.accessoryGap)
                    .fixedSize()
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsAreaControls {
                areaAccessories
                    .padding(.leading, presenter.barFrameInPanel.width + BarMetrics.accessoryGap)
                    .fixedSize()
                    .transition(accessoryTransition)
            }
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(BarCoordinateSpace.panel))
        } action: {
            presenter.barFrameInPanel = $0
        }
    }

    private var areaAccessories: some View {
        VStack(alignment: .leading, spacing: BarMetrics.accessoryGap) {
            if showsStartFlyout {
                RecordingStartFlyout(presentedHoverMode: presenter.renderHoveredOutputMode)
                    .transition(.opacity.animation(.easeOut(duration: 0.15)))
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(BarCoordinateSpace.panel))
                    } action: {
                        presenter.startFlyoutFrameInPanel = $0
                    }
                    .onDisappear {
                        presenter.startFlyoutFrameInPanel = nil
                    }
            }

            RecordingAreaBarPill()
                .frame(height: BarMetrics.height)
                .onGeometryChange(for: CGRect.self) {
                    $0.frame(in: .named(BarCoordinateSpace.panel))
                } action: {
                    presenter.areaPillFrameInPanel = $0
                }
                .onDisappear {
                    presenter.areaPillFrameInPanel = nil
                }
        }
        .fixedSize()
    }

    private var controlRow: some View {
        HStack(spacing: 0) {
            BarDragHandle()

            Group {
                switch presenter.mode {
                case .picker:
                    RecordingPickerControls()
                case .recording:
                    RecordingSessionControls()
                }
            }
            .transition(.asymmetric(insertion: .opacity, removal: .identity))
        }
        .fixedSize()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }

    private var visibilityToast: some View {
        InterfaceToast(
            "Upshot windows will be captured",
            systemImage: "exclamationmark.triangle.fill",
            actionTitle: "Exclude"
        ) {
            includeAppWindowsInCaptures = false
        }
        .accessibilityHint("Hides Upshot windows from screenshots and recordings")
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(BarCoordinateSpace.panel))
        } action: {
            presenter.visibilityToastFrameInPanel = $0
        }
    }
}

extension RecordingBarPresenter {
    func installRenderMode(recording: Bool, teleprompter: Bool = false, hoveredOutputMode: RecordingOutputMode? = nil) {
        precondition(UpshotStorage.isRenderingStates)
        mode = recording ? .recording : .picker
        isTeleprompterOpen = teleprompter
        renderHoveredOutputMode = hoveredOutputMode
    }
}
