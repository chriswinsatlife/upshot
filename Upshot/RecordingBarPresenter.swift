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

    var barFrameInPanel: CGRect = .zero
    var visibilityBannerFrameInPanel: CGRect = .zero
    var areaPillFrameInPanel: CGRect?

    func containsPanelPoint(_ point: CGPoint) -> Bool {
        if barFrameInPanel.contains(point) { return true }
        if let areaPillFrameInPanel, areaPillFrameInPanel.contains(point) { return true }
        return mode == .picker
            && UpshotPreferences.includeAppWindowsInCaptures
            && visibilityBannerFrameInPanel.contains(point)
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
        BarControlHoverView.endActiveHover()
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
        return CGRect(
            x: panel.frame.minX + barFrameInPanel.minX,
            y: panel.frame.maxY - barFrameInPanel.maxY,
            width: barFrameInPanel.width,
            height: barFrameInPanel.height
        )
    }

    var areaPillFrame: CGRect? {
        guard let panel, panel.isVisible, let frame = areaPillFrameInPanel else { return nil }
        return CGRect(
            x: panel.frame.minX + frame.minX,
            y: panel.frame.maxY - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func isPositioned(_ panel: NSPanel, onDisplayID displayID: CGDirectDisplayID?) -> Bool {
        guard let target = ActiveDisplayResolver.screen(for: displayID) else { return true }
        return target.frame.intersects(panel.frame)
    }

    private func position(_ panel: NSPanel, displayID: CGDirectDisplayID?) {
        let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 800, height: 600)
        let size = CGSize(width: BarMetrics.panelWidth, height: BarMetrics.panelHeight)
        let origin = CGPoint(
            x: visibleFrame.midX - size.width / 2,
            y: visibleFrame.minY + 48 - BarMetrics.bottomSlack
        )
        panel.setFrame(CGRect(origin: origin, size: size), display: true)
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
    @State private var tooltip = BarTooltipModel()
    @State private var rowWidth: CGFloat = 0
    @AppStorage(UpshotPreferences.includeAppWindowsInCapturesKey)
    private var includeAppWindowsInCaptures = false

    var body: some View {
        bar
            .padding(.bottom, BarMetrics.bottomSlack)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .coordinateSpace(.named(BarCoordinateSpace.panel))
            .environment(tooltip)
            .onChange(of: includeAppWindowsInCaptures) { _, _ in
                guard !UpshotStorage.isRenderingStates else { return }
                PreviewWindowCaptureExclusion.shared.refreshRegisteredWindows()
                Task { await RecordingSourceCatalog.shared.refresh() }
            }
    }

    private var showsTeleprompter: Bool {
        presenter.mode == .picker && presenter.isTeleprompterOpen
    }

    private var bar: some View {
        VStack(spacing: 0) {
            if showsTeleprompter {
                RecordingBarTeleprompter()
                    .frame(width: rowWidth)
                    .transition(.opacity)
            }

            controlRow
        }
        .clipShape(barShape)
        .glassEffect(.regular, in: barShape)
        .overlay {
            barShape.strokeBorder(BarMetrics.edge, lineWidth: 0.5)
        }
        .background(alignment: .bottom) {
            if presenter.mode == .picker && includeAppWindowsInCaptures {
                visibilityBanner
                    .padding(.horizontal, BarMetrics.visibilityBannerInset)
                    .offset(y: BarMetrics.visibilityBannerHeight - BarMetrics.visibilityBannerOverlap)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if presenter.mode == .picker && area.isActive {
                RecordingAreaBarPill()
                    .alignmentGuide(.trailing) { $0[.leading] - BarMetrics.pillGap }
                    .transition(
                        .opacity.combined(with: .offset(x: -12))
                            .animation(.easeOut(duration: 0.18))
                    )
                    .onGeometryChange(for: CGRect.self) {
                        $0.frame(in: .named(BarCoordinateSpace.panel))
                    } action: {
                        presenter.areaPillFrameInPanel = $0
                    }
                    .onDisappear {
                        presenter.areaPillFrameInPanel = nil
                    }
            }
        }
        .overlay(alignment: .bottom) {
            tooltipLayer.frame(height: BarMetrics.height)
        }
        .coordinateSpace(.named(BarCoordinateSpace.bar))
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(BarCoordinateSpace.panel))
        } action: {
            presenter.barFrameInPanel = $0
        }
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
        .padding(.leading, 2)
        .padding(.trailing, BarMetrics.horizontalPadding)
        .frame(height: BarMetrics.height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
    }

    private var visibilityBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Palette.warning)
                .accessibilityHidden(true)
            Text("Upshot windows will be captured")
                .foregroundStyle(BarMetrics.activeTint)
            Spacer(minLength: 8)
            InspectorToggle("Include Upshot windows in captures", isOn: $includeAppWindowsInCaptures)
                .accessibilityHint("Turn off to hide Upshot windows from screenshots and recordings")
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.top, BarMetrics.visibilityBannerOverlap)
        .frame(maxWidth: .infinity)
        .frame(height: BarMetrics.visibilityBannerHeight)
        .glassEffect(.regular, in: visibilityBannerShape)
        .overlay {
            visibilityBannerShape
                .strokeBorder(BarMetrics.edge, lineWidth: 0.5)
        }
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .named(BarCoordinateSpace.panel))
        } action: {
            presenter.visibilityBannerFrameInPanel = $0
        }
    }

    private var visibilityBannerShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: 12,
            bottomTrailingRadius: 12,
            topTrailingRadius: 0,
            style: .continuous
        )
    }

    private var tooltipLayer: some View {
        GeometryReader { _ in
            if let target = tooltip.visible {
                BarTooltipPill(text: target.text)
                    .position(
                        x: target.frame.midX,
                        y: -(BarTooltip.gap + BarTooltip.pillHeight / 2)
                    )
            }
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.12), value: tooltip.visible?.id)
        .animation(.easeOut(duration: 0.12), value: tooltip.visible?.text)
    }

    private var barShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: showsTeleprompter ? BarMetrics.expandedCornerRadius : BarMetrics.cornerRadius,
            style: .continuous
        )
    }
}

extension RecordingBarPresenter {
    func installRenderMode(recording: Bool, teleprompter: Bool = false) {
        precondition(UpshotStorage.isRenderingStates)
        mode = recording ? .recording : .picker
        isTeleprompterOpen = teleprompter
    }
}
