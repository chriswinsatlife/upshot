import AppKit
import SwiftUI

@MainActor
@Observable
final class CaptureCountdownPresenter {
    static let shared = CaptureCountdownPresenter()

    private var panel: NSPanel?

    private init() {}

    private(set) var isRunning = false
    private var runID: UUID?
    private var countdownTask: Task<Bool, Never>?
    private var escapeMonitor: Any?
    private var globalEscapeMonitor: Any?

    func runIfNeeded(seconds: Int, displayID: CGDirectDisplayID?) async -> Bool {
        guard !isRunning, !Task.isCancelled else { return false }
        guard seconds > 0 else { return true }
        let id = UUID()
        AppLog.event("capture", "capture_countdown_started", fields: ["seconds": String(describing: seconds)])
        runID = id
        isRunning = true
        installEscapeMonitors()
        let task = Task { @MainActor in
            guard runID == id, !Task.isCancelled else { return false }
            let model = CaptureCountdownModel(remaining: seconds, total: seconds)
            present(model: model, displayID: displayID)
            do {
                for value in stride(from: seconds, through: 1, by: -1) {
                    try Task.checkCancellation()
                    model.remaining = value
                    try await Task.sleep(for: .seconds(1))
                }
                dismiss()
                try await Task.sleep(for: .milliseconds(80))
                try Task.checkCancellation()
                return true
            } catch {
                return false
            }
        }
        countdownTask = task
        let completed = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        guard runID == id else { return false }
        AppLog.event("capture", "capture_countdown_finished", fields: ["completed": String(describing: completed)])
        cancel()
        return completed && !Task.isCancelled
    }

    func cancel() {
        if isRunning { AppLog.event("capture", "capture_countdown_dismissed") }
        countdownTask?.cancel()
        countdownTask = nil
        runID = nil
        isRunning = false
        dismiss()
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let globalEscapeMonitor { NSEvent.removeMonitor(globalEscapeMonitor) }
        escapeMonitor = nil
        globalEscapeMonitor = nil
    }

    private func installEscapeMonitors() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.cancel()
            return nil
        }
        globalEscapeMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func present(model: CaptureCountdownModel, displayID: CGDirectDisplayID?) {
        dismiss()

        let hostingView = NSHostingView(rootView: CaptureCountdownView(model: model, onCancel: { [weak self] in self?.cancel() }))
        hostingView.sizingOptions = []
        let size = hostingView.fittingSize

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = hostingView
        panel.setFrame(NSRect(origin: centeredOrigin(size: size, displayID: displayID), size: size), display: true)
        panel.orderFrontRegardless()

        self.panel = panel
    }

    private func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func centeredOrigin(size: NSSize, displayID: CGDirectDisplayID?) -> CGPoint {
        let screen = screen(for: displayID) ?? NSScreen.main
        guard let frame = screen?.frame else { return .zero }
        return Self.centeredOrigin(size: size, screenFrame: frame)
    }

    static func centeredOrigin(size: NSSize, screenFrame frame: CGRect) -> CGPoint {
        CGPoint(
            x: frame.midX - size.width / 2,
            y: frame.midY - size.height / 2
        )
    }

    private func screen(for displayID: CGDirectDisplayID?) -> NSScreen? {
        guard let displayID else { return nil }
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        }
    }
}

@MainActor
@Observable
final class CaptureCountdownModel {
    var remaining: Int
    let total: Int

    init(remaining: Int, total: Int) {
        self.remaining = remaining
        self.total = max(1, total)
    }
}

struct CaptureCountdownView: View {
    static let windowMargin: CGFloat = 32

    @State var model: CaptureCountdownModel
    let onCancel: () -> Void

    @State private var ring: Double = 1
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InterfacePanel(.panel) {
            HStack(spacing: 0) {
                dial
                InterfaceToolbarDivider()
                InterfaceToolbarButton("Cancel", systemImage: "xmark", action: onCancel)
            }
            .fixedSize()
        }
        .padding(Self.windowMargin)
        .onAppear { drain(from: model.remaining) }
        .onChange(of: model.remaining) { _, value in drain(from: value) }
    }

    private var dial: some View {
        ZStack {
            Circle()
                .stroke(Palette.floatingDivider, lineWidth: 3)
            Circle()
                .trim(from: 0, to: ring)
                .stroke(Palette.label, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(model.remaining)")
                .font(.dsDisplay)
                .monospacedDigit()
                .foregroundStyle(Palette.label)
                .contentTransition(.numericText(countsDown: true))
                .motion(.morphQuick, value: model.remaining)
        }
        .padding(Space.xs)
        .frame(width: InterfaceMetrics.toolbarButtonMinimumWidth, height: InterfaceMetrics.toolbarButtonHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Capturing in \(model.remaining)")
    }

    private func drain(from value: Int) {
        if UpshotStorage.isRenderingStates { ring = Double(value) / Double(model.total); return }
        let start = Double(value) / Double(model.total)
        let end = Double(value - 1) / Double(model.total)
        ring = start
        withAnimation(reduceMotion ? nil : .linear(duration: 1)) { ring = end }
    }
}
