import AppKit

@MainActor
final class ScrollingCaptureControlPanel: NSObject, NSWindowDelegate {
    enum Mode {
        case manual
        case automatic
    }

    var onStart: ((Mode) -> Void)?
    var onStop: (() -> Void)?
    var onCancel: (() -> Void)?

    private let panel: NSPanel
    private let modeControl = NSSegmentedControl(labels: ["Manual", "Auto-Scroll"], trackingMode: .selectOne, target: nil, action: nil)
    private let heightLabel = NSTextField(labelWithString: "Height: 0 px")
    private let statusLabel = NSTextField(wrappingLabelWithString: "Select the scrolling content only. Press Start, then scroll down slowly.")
    private let startButton = NSButton(title: "Start", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)

    var windowID: CGWindowID { CGWindowID(panel.windowNumber) }
    var frame: CGRect { panel.frame }

    init(rect: CGRect) {
        panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 360, height: 178),
                        styleMask: [.titled, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "Scrolling Capture"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self

        heightLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .medium)
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.maximumNumberOfLines = 3
        modeControl.selectedSegment = 0
        modeControl.target = self
        modeControl.action = #selector(changeMode)
        for button in [startButton, stopButton, cancelButton] { button.bezelStyle = .rounded }
        startButton.target = self
        startButton.action = #selector(startCapture)
        stopButton.target = self
        stopButton.action = #selector(stopCapture)
        stopButton.isEnabled = false
        cancelButton.target = self
        cancelButton.action = #selector(cancelCapture)
        cancelButton.keyEquivalent = "\u{1b}"

        let heading = NSStackView(views: [modeControl, NSView(), heightLabel])
        heading.orientation = .horizontal
        heading.alignment = .centerY
        let buttons = NSStackView(views: [NSView(), startButton, stopButton, cancelButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let content = NSStackView(views: [heading, statusLabel, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(content)
        panel.contentView = container
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
            heading.widthAnchor.constraint(equalTo: content.widthAnchor),
            statusLabel.widthAnchor.constraint(equalTo: content.widthAnchor),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor)
        ])
        position(around: rect)
    }

    func show() { panel.orderFrontRegardless() }

    func close() {
        panel.orderOut(nil)
        panel.delegate = nil
        onStart = nil
        onStop = nil
        onCancel = nil
    }

    func update(height: Int, status: String, running: Bool, hasFrames: Bool, finishing: Bool = false, canStart: Bool = true) {
        heightLabel.stringValue = "Height: \(height) px"
        statusLabel.stringValue = status
        startButton.isEnabled = !running && !finishing && canStart
        stopButton.isEnabled = hasFrames && !finishing
        modeControl.isEnabled = !running && !finishing && canStart
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

    @objc private func changeMode() {
        statusLabel.stringValue = modeControl.selectedSegment == 0
            ? "Press Start, then scroll down slowly inside the selected area."
            : "Press Start to scroll down automatically. Stop saves the image."
    }

    @objc private func startCapture() { onStart?(modeControl.selectedSegment == 0 ? .manual : .automatic) }
    @objc private func stopCapture() { onStop?() }
    @objc private func cancelCapture() { onCancel?() }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCancel?()
        return false
    }
}

extension ScrollingCaptureControlPanel {
    static func renderContent(running: Bool, automatic: Bool, finishing: Bool) -> NSView {
        precondition(UpshotStorage.isRenderingStates)
        let control = ScrollingCaptureControlPanel(rect: .zero)
        control.panel.level = StateRenderer.renderLevel
        control.modeControl.selectedSegment = automatic ? 1 : 0
        control.update(height: running || finishing ? 2460 : 0,
                       status: finishing ? "Stitching captured frames…" : running ? "Scroll down slowly inside the selected area. Stop saves the image." : "Select the scrolling content only. Press Start, then scroll down slowly.",
                       running: running, hasFrames: running, finishing: finishing)
        let content = control.panel.contentView!
        control.panel.contentView = nil
        control.close()
        return content
    }
}
