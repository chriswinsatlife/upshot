import AppKit
import CoreGraphics
import SwiftUI

@MainActor
final class CaptureShelfPresenter {
    static let shared = CaptureShelfPresenter()

    var onAnnotate: ((URL) -> Void)?
    var onEditVideo: ((URL) -> Void)?

    private var panel: NSPanel?
    private var targetDisplayID: CGDirectDisplayID?
    private var keyMonitor: Any?
    private var globalKeyMonitor: Any?
    private var screenObserver: NSObjectProtocol?

    private init() {}

    func setTargetDisplay(_ displayID: CGDirectDisplayID?) {
        targetDisplayID = displayID ?? ActiveDisplayResolver.activeDisplayID()
        applyPlacement()
    }

    func show(displayID: CGDirectDisplayID?) {
        let panel = panel ?? makePanel()
        setTargetDisplay(displayID)
        panel.orderFrontRegardless()
        Task { @MainActor [weak panel] in
            try? await Task.sleep(for: .milliseconds(150))
            panel?.orderFrontRegardless()
        }
    }

    func closeIfEmpty() {
        guard CaptureShelf.shared.items.isEmpty, let panel else { return }
        QuickLookPreviewPresenter.dismiss()
        panel.orderOut(nil)
        panel.contentView = nil
        self.panel = nil
        removeMonitors()
    }

    func applyPlacement() {
        guard let panel, let screen = targetScreen() else { return }
        let visible = screen.visibleFrame.integral
        let width = CaptureShelfMetrics.panelWidth
        let x = UpshotPreferences.previewPosition == .left ? visible.minX : visible.maxX - width
        let frame = CGRect(x: x, y: visible.minY, width: width, height: visible.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: panel.isVisible)
        }
    }

    private func targetScreen() -> NSScreen? {
        ActiveDisplayResolver.screen(for: targetDisplayID) ?? ActiveDisplayResolver.activeScreen()
    }

    private func makePanel() -> NSPanel {
        let panel = CaptureShelfPanel(
            contentRect: CGRect(x: 0, y: 0, width: CaptureShelfMetrics.panelWidth, height: 600),
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
        panel.level = .screenSaver
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        PreviewWindowCaptureExclusion.shared.register(window: panel)

        let hostingView = CaptureShelfHostingView(rootView: CaptureShelfView())
        panel.contentView = hostingView

        self.panel = panel
        installMonitors()
        return panel
    }


    private func installMonitors() {
        CaptureShelfKeyboardShortcuts.shared.start()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            Self.handleKey(event) ? nil : event
        }
        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 49 || event.keyCode == 53 else { return }
            _ = Self.handleKey(event)
        }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { CaptureShelfPresenter.shared.applyPlacement() }
        }
    }

    private func removeMonitors() {
        CaptureShelfKeyboardShortcuts.shared.stop()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let globalKeyMonitor { NSEvent.removeMonitor(globalKeyMonitor) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        keyMonitor = nil
        globalKeyMonitor = nil
        screenObserver = nil
    }

    private static func handleKey(_ event: NSEvent) -> Bool {
        guard !event.isARepeat,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return false }
        let shelf = CaptureShelf.shared
        switch event.keyCode {
        case 53 where QuickLookPreviewPresenter.isShown:
            QuickLookPreviewPresenter.dismiss()
            return true
        case 49:
            guard let item = shelf.hoveredItem else { return false }
            if QuickLookPreviewPresenter.isShown, QuickLookPreviewPresenter.currentURL == item.url {
                QuickLookPreviewPresenter.dismiss()
            } else {
                shelf.quickLook(id: item.id)
            }
            return true
        default:
            guard !QuickLookPreviewPresenter.isShown else { return false }
            guard let action = CaptureShelfKeyboardShortcuts.action(for: event) else { return false }
            guard let item = shelf.hoveredItem, CaptureShelf.performHoveredAction(action) else { return false }
            NSLog("Quick Access hover shortcut item=%@ action=%@ outcome=dispatched", item.id.uuidString, action.rawValue)
            return true
        }
    }
}

enum CaptureShelfMetrics {
    static var cardSize: CGSize {
        let scale = UpshotPreferences.previewOverlaySize.scale
        return CGSize(width: 168 * scale, height: 118 * scale)
    }
    static let cardRadius: CGFloat = 14
    static let cardSpacing: CGFloat = 12
    static let edgeInset: CGFloat = 20
    static let bottomInset: CGFloat = 24
    static let headerHeight: CGFloat = 26
    static let headerSpacing: CGFloat = 10
    static let shadowRoom: CGFloat = 28
    static var panelWidth: CGFloat { edgeInset + cardSize.width + shadowRoom }

    static func capacity(forHeight height: CGFloat) -> Int {
        let usable = height - bottomInset - headerHeight - headerSpacing - edgeInset
        let stride = cardSize.height + cardSpacing
        return max(1, Int((usable + cardSpacing) / stride))
    }
}

private final class CaptureShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class CaptureShelfHostingView<Content: View>: NSHostingView<Content> {
    private var swipeDistance = CGSize.zero
    private var swipeItemID: ShelfItem.ID?
    private var swipeStartedTucked = false

    required init(rootView: Content) {
        super.init(rootView: rootView)
        sizingOptions = []
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func scrollWheel(with event: NSEvent) {
        guard event.hasPreciseScrollingDeltas, event.momentumPhase.isEmpty else { return }
        let shelf = CaptureShelf.shared
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipeDistance = .zero
            swipeItemID = shelf.hoveredID
            swipeStartedTucked = shelf.isTucked
        }
        if event.phase.contains(.cancelled) {
            swipeDistance = .zero
            swipeItemID = nil
            NSLog("Quick Access swipe outcome=cancelled")
            return
        }

        swipeDistance.width += event.scrollingDeltaX
        swipeDistance.height += event.scrollingDeltaY
        guard event.phase.contains(.ended) else { return }
        let distance = swipeDistance
        let itemID = swipeItemID
        swipeDistance = .zero
        swipeItemID = nil
        guard abs(distance.width) > 36, abs(distance.width) > abs(distance.height),
              shelf.isTucked == swipeStartedTucked, !shelf.isMoving, shelf.draggingID == nil else { return }

        let towardEdge: CGFloat = UpshotPreferences.previewPosition == .left ? -1 : 1
        let swipedTowardEdge = distance.width * towardEdge > 0
        if shelf.isTucked {
            if !swipedTowardEdge {
                shelf.open()
                NSLog("Quick Access swipe action=openShelf outcome=dispatched")
            }
            return
        }

        let action = swipedTowardEdge
            ? UpshotPreferences.previewSwipeTowardEdgeAction
            : UpshotPreferences.previewSwipeAwayFromEdgeAction
        let performed: Bool
        if action == .tuck {
            shelf.tuck(.user)
            performed = true
        } else if let itemID, let cardAction = action.cardAction {
            performed = shelf.perform(cardAction, id: itemID)
        } else {
            performed = false
        }
        NSLog("Quick Access swipe item=%@ direction=%@ action=%@ outcome=%@", itemID?.uuidString ?? "none", swipedTowardEdge ? "towardEdge" : "awayFromEdge", action.rawValue, performed ? "dispatched" : "ignored")
    }
}
