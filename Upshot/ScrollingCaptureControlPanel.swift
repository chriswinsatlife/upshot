import AppKit
import SwiftUI

@MainActor
final class ScrollingCaptureControlPanel {
    enum Mode {
        case manual
        case automatic

        var logValue: String {
            switch self {
            case .manual: "manual"
            case .automatic: "automatic"
            }
        }

        var title: String {
            switch self {
            case .manual: "Manual"
            case .automatic: "Auto-Scroll"
            }
        }

        var systemImage: String {
            switch self {
            case .manual: "computermouse"
            case .automatic: "chevron.down.2"
            }
        }
    }

    var onStart: ((Mode) -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private let panel: ScrollingCaptureControlWindow
    private let hostingView: NSHostingView<ScrollingCaptureControlsView>
    private let selectionRect: CGRect
    private var state = ScrollingCaptureControlState()

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }
    var frame: CGRect { panel.frame }

    init(rect: CGRect) {
        selectionRect = rect
        panel = ScrollingCaptureControlWindow(contentRect: .zero,
                                              styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                                              backing: .buffered, defer: false)
        hostingView = NSHostingView(rootView: ScrollingCaptureControlsView(state: state, actions: .inactive))
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.onCancelOperation = { [weak self] in self?.onCancel?() }

        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        refresh()
    }

    func show() { panel.orderFrontRegardless() }

    func close() {
        panel.orderOut(nil)
        panel.onCancelOperation = nil
        onStart = nil
        onStop = nil
        onCancel = nil
    }

    func update(height: Int, status: String, running: Bool, hasFrames: Bool, finishing: Bool = false, canStart: Bool = true) {
        state.height = height
        state.isRunning = running
        state.hasFrames = hasFrames
        state.isFinishing = finishing
        state.canStart = canStart
        state.status = ScrollingCaptureControlStatus(message: status, mode: state.mode, running: running, hasFrames: hasFrames,
                                                     finishing: finishing, canStart: canStart)
        refresh()
    }

    private func select(_ mode: Mode) {
        guard state.canChooseMode, state.mode != mode else { return }
        state.mode = mode
        state.status = .ready(mode)
        AppLog.event("capture", "scrolling_capture_mode_selected", fields: ["mode": mode.logValue])
        refresh()
    }

    private func refresh() {
        hostingView.rootView = ScrollingCaptureControlsView(state: state, actions: actions)
        let fittingSize = hostingView.fittingSize
        let size = CGSize(width: fittingSize.width.rounded(.up), height: fittingSize.height.rounded(.up))
        guard size != panel.frame.size else { return }
        panel.setContentSize(size)
        position(around: selectionRect)
        AppLog.unifiedEvent("capture", "scrolling_capture_controls_resized", fields: ["height": String(describing: size.height), "width": String(describing: size.width)])
    }

    private var actions: ScrollingCaptureControlActions {
        ScrollingCaptureControlActions(
            select: { [weak self] mode in self?.select(mode) },
            start: { [weak self] in
                guard let self else { return }
                onStart?(state.mode)
            },
            stop: { [weak self] in self?.onStop?() },
            cancel: { [weak self] in self?.onCancel?() }
        )
    }

    private func position(around rect: CGRect) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let candidates = [
            CGRect(x: rect.midX - size.width / 2, y: rect.minY - size.height - 12, width: size.width, height: size.height),
            CGRect(x: rect.midX - size.width / 2, y: rect.maxY + 12, width: size.width, height: size.height),
            CGRect(x: rect.maxX + 12, y: rect.midY - size.height / 2, width: size.width, height: size.height),
            CGRect(x: rect.minX - size.width - 12, y: rect.midY - size.height / 2, width: size.width, height: size.height)
        ]
        let desired = candidates.first { visible.contains($0) }
            ?? CGRect(x: visible.midX - size.width / 2, y: visible.minY + 24, width: size.width, height: size.height)
        panel.setFrameOrigin(CGPoint(x: max(visible.minX, min(desired.minX, visible.maxX - size.width)),
                                    y: max(visible.minY, min(desired.minY, visible.maxY - size.height))))
    }
}

private final class ScrollingCaptureControlWindow: NSPanel {
    var onCancelOperation: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        onCancelOperation?()
    }
}

struct ScrollingCaptureControlState: Equatable {
    var mode: ScrollingCaptureControlPanel.Mode = .manual
    var height = 0
    var status = ScrollingCaptureControlStatus.ready(.manual)
    var isRunning = false
    var hasFrames = false
    var isFinishing = false
    var canStart = true

    var canChooseMode: Bool { !isRunning && !isFinishing && canStart }
    var canStartCapture: Bool { !isRunning && !isFinishing && canStart }
    var canStop: Bool { hasFrames && !isFinishing }
}

struct ScrollingCaptureControlStatus: Equatable {
    let title: String
    let detail: String?
    let systemImage: String
    let tone: InterfaceToastTone

    static func ready(_ mode: ScrollingCaptureControlPanel.Mode) -> ScrollingCaptureControlStatus {
        switch mode {
        case .manual:
            ScrollingCaptureControlStatus(title: "Press Start, then scroll down slowly", detail: nil, systemImage: mode.systemImage, tone: .neutral)
        case .automatic:
            ScrollingCaptureControlStatus(title: "Press Start to scroll down automatically", detail: nil, systemImage: mode.systemImage, tone: .neutral)
        }
    }

    init(title: String, detail: String?, systemImage: String, tone: InterfaceToastTone) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
    }

    init(message: String, mode: ScrollingCaptureControlPanel.Mode, running: Bool, hasFrames: Bool, finishing: Bool, canStart: Bool) {
        let sentenceBreak = message.range(of: ". ")
        let firstSentence = sentenceBreak.map { String(message[..<$0.lowerBound]) } ?? message
        let remainder = sentenceBreak.map { String(message[$0.upperBound...]).trimmingCharacters(in: .whitespaces) }
        title = firstSentence.hasSuffix(".") ? String(firstSentence.dropLast()) : firstSentence
        detail = remainder?.isEmpty == false && !(running && !hasFrames) ? remainder : nil
        if finishing {
            systemImage = "hourglass"
            tone = .neutral
        } else if running {
            systemImage = mode.systemImage
            tone = .neutral
        } else if !canStart {
            systemImage = "exclamationmark.circle"
            tone = .neutral
        } else {
            systemImage = "exclamationmark.triangle.fill"
            tone = .failure
        }
    }
}

struct ScrollingCaptureControlActions {
    let select: (ScrollingCaptureControlPanel.Mode) -> Void
    let start: () -> Void
    let stop: () -> Void
    let cancel: () -> Void

    static let inactive = ScrollingCaptureControlActions(select: { _ in }, start: {}, stop: {}, cancel: {})
}

struct ScrollingCaptureControlsView: View {
    let state: ScrollingCaptureControlState
    let actions: ScrollingCaptureControlActions

    var body: some View {
        VStack(spacing: Space.m) {
            ScrollingCaptureToolbar(state: state, actions: actions)
            InterfaceToast(state.status.title,
                           detail: state.status.detail,
                           systemImage: state.status.systemImage,
                           tone: state.status.tone)
        }
        .fixedSize()
    }
}

private struct ScrollingCaptureToolbar: View {
    let state: ScrollingCaptureControlState
    let actions: ScrollingCaptureControlActions

    var body: some View {
        InterfacePanel {
            HStack(spacing: Space.xxs) {
                ForEach([ScrollingCaptureControlPanel.Mode.manual, .automatic], id: \.self) { mode in
                    InterfaceToolbarButton(mode.title, systemImage: mode.systemImage, isSelected: state.mode == mode) {
                        actions.select(mode)
                    }
                }
                .disabled(!state.canChooseMode)
                InterfaceToolbarDivider()
                ScrollingCaptureHeightReadout(height: state.height)
                InterfaceToolbarDivider()
                InterfaceToolbarButton("Start", systemImage: "play.circle", action: actions.start)
                    .disabled(!state.canStartCapture)
                InterfaceToolbarButton("Stop", systemImage: "stop.circle", tint: Palette.record, action: actions.stop)
                    .disabled(!state.canStop)
                InterfaceToolbarButton("Cancel", systemImage: "xmark.circle", action: actions.cancel)
            }
            .fixedSize()
        }
    }
}

private struct ScrollingCaptureHeightReadout: View {
    let height: Int

    var body: some View {
        VStack(spacing: InterfaceMetrics.toolbarIconToLabelSpacing) {
            ZStack {
                InterfaceValueWithUnitLabel(value: ScrollingCaptureOutputLimits.maximumHeight.formatted(.number), unit: "px")
                    .hidden()
                InterfaceValueWithUnitLabel(value: height.formatted(.number), unit: "px")
            }
            .frame(height: Space.xxl)
            Text("Height")
                .font(.dsToolbarLabel)
                .foregroundStyle(Palette.secondaryLabel)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, Space.m)
        .frame(minWidth: InterfaceMetrics.toolbarButtonMinimumWidth, minHeight: InterfaceMetrics.toolbarButtonHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Height")
        .accessibilityValue("\(height) pixels")
    }
}

extension ScrollingCaptureControlPanel {
    enum RenderState: String, CaseIterable {
        case manualReady = "manual-ready"
        case automaticReady = "automatic-ready"
        case automaticPermissionDenied = "automatic-permission-denied"
        case starting
        case running
        case automaticRunning = "automatic-running"
        case reversed
        case waitingForOverlap = "waiting-for-overlap"
        case paused
        case automaticStopped = "automatic-stopped"
        case maximumLength = "maximum-length"
        case finishing
        case saving
        case saveFailed = "save-failed"
    }

    static func renderView(_ renderState: RenderState) -> AnyView {
        precondition(UpshotStorage.isRenderingStates)
        let control = ScrollingCaptureControlPanel(rect: .zero)
        control.panel.level = StateRenderer.renderLevel
        switch renderState {
        case .manualReady:
            break
        case .automaticReady:
            control.state.mode = .automatic
            control.state.status = .ready(.automatic)
        case .automaticPermissionDenied:
            control.state.mode = .automatic
            control.update(height: 0, status: "Enable Accessibility for Auto-Scroll, or choose Manual.", running: false, hasFrames: false)
        case .starting:
            control.update(height: 0, status: "Scroll down slowly inside the selected area. Stop saves the image.", running: true, hasFrames: false)
        case .running:
            control.update(height: 2460, status: "Scroll down slowly. Stop saves the image.", running: true, hasFrames: true)
        case .automaticRunning:
            control.state.mode = .automatic
            control.update(height: 7380, status: "Auto-Scroll is running. Stop saves the image.", running: true, hasFrames: true)
        case .reversed:
            control.update(height: 2460, status: "Scroll down past the captured content to continue.", running: true, hasFrames: true)
        case .waitingForOverlap:
            control.update(height: 2460, status: "Waiting for matching content. Scroll slowly.", running: true, hasFrames: true)
        case .paused:
            control.update(height: 2460, status: ScrollingCaptureError.unverifiedOverlap.localizedDescription, running: false, hasFrames: true)
        case .automaticStopped:
            control.state.mode = .automatic
            control.update(height: 7380, status: "\(ScrollingCaptureAutoScroll.Failure.moved.localizedDescription) Stop saves captured content.", running: false, hasFrames: true)
        case .maximumLength:
            control.update(height: ScrollingCaptureOutputLimits.maximumHeight, status: "Maximum length reached", running: false, hasFrames: true, canStart: false)
        case .finishing:
            control.update(height: 2460, status: "Finishing scrolling capture…", running: true, hasFrames: true, finishing: true)
        case .saving:
            control.update(height: 2460, status: "Saving scrolling capture…", running: true, hasFrames: true, finishing: true)
        case .saveFailed:
            control.update(height: 2460, status: "Save failed. Press Stop to retry, or Cancel.", running: false, hasFrames: true)
        }
        let view = ScrollingCaptureControlsView(state: control.state, actions: .inactive)
        control.close()
        return AnyView(view)
    }
}
