import AppKit
import ScreenCaptureKit
import SwiftUI

struct AreaCaptureSelectionResult {
    enum Kind {
        case area
        case element
        case window(CGWindowID)
        case fullscreen(CGDirectDisplayID)
        case scrolling
        case recording(RecordingOutputMode)
    }

    let kind: Kind
    let rect: CGRect
    var snapshots: [AreaCaptureSnapshot]
    let frozen: Bool
    let source: CaptureSource?
    var cursor: ScreenshotCursorSnapshot?
    var skipBackgroundPreset = false
    var capturedAt = Date()
    var composedImage: CGImage?
    var selectionTime: TimeInterval?
    var desktopIconLease: UUID?
    var composedImageScale: CGFloat?
    var windowIncludesShadow = false
    var windowShowsCursor = false
    var delaySeconds = 0
    var recognizesText = false

    func logTiming(composedAt time: TimeInterval, acquisition: String, frames: [AreaCaptureSnapshot]? = nil) {
        guard let selectionTime else { return }
        for snapshot in frames ?? snapshots where snapshot.frame.intersects(rect) {
            if let presentationTime = snapshot.presentationTime {
                AppLog.event("capture", "area_capture_timing_measured", fields: ["acquisition": acquisition, "display": String(describing: snapshot.displayID), "selection_to_frame_ms": String(format: "%.3f", (presentationTime - selectionTime) * 1000), "selection_to_composed_ms": String(format: "%.3f", (time - selectionTime) * 1000)])
            } else {
                AppLog.event("capture", "area_capture_timing_measured", fields: ["acquisition": acquisition, "display": String(describing: snapshot.displayID), "selection_to_frame_ms": "unavailable", "selection_to_composed_ms": String(format: "%.3f", (time - selectionTime) * 1000)])
            }
        }
    }
}

@MainActor
@Observable
final class AreaCaptureSelection {
    static let shared = AreaCaptureSelection()

    struct WindowTarget {
        let id: CGWindowID
        let processID: pid_t
        let frame: CGRect
        let source: CaptureSource
    }

    private var panels: [NSPanel] = []
    private var views: [AreaCaptureSelectionView] = []
    private var continuation: CheckedContinuation<AreaCaptureSelectionResult?, Never>?
    private var snapshots: [AreaCaptureSnapshot] = []
    private var windows: [WindowTarget] = []
    private var screenObserver: NSObjectProtocol?
    private var streams: [AreaCaptureFrameStream] = []
    private var shareableContent: SCShareableContent?
    private var contentTask: Task<Void, Never>?
    private var contentError: Error?
    private var startupTask: Task<Void, Never>?
    private var windowStream: AreaCaptureFrameStream?
    private var windowStreamTask: Task<Void, Never>?
    private var desiredWindowID: CGWindowID?
    private var currentWindowID: CGWindowID?
    private var selectionTask: Task<Void, Never>?
    private var completingSelection = false
    private var desktopIconLease: UUID?
    private var selectionError: Error?
    private var cancelled = false
    private var delaySeconds = 0
    private var requestedDelaySeconds = 0
    private var includeWindowShadow = false
    private var windowShowsCursor = false
    private var sessionID = UUID()
    private var active = false
    private var cursor: ScreenshotCursorSnapshot?
    private var frozen = true
    private(set) var isAllInOne = false
    private var isScrollingOnly = false
    private(set) var mode: AllInOneCaptureMode = .area
    private(set) var start: CGPoint?
    private(set) var pointer = CGPoint.zero
    private(set) var highlightedRect: CGRect?
    private var hoveredWindow: WindowTarget?
    private(set) var status: String?
    private(set) var selfTimerArmed = false
    private(set) var textRecognitionArmed = false
    private(set) var aspect: RecordingAreaAspect?

    var instruction: String {
        if let status { return status }
        switch mode {
        case .area: return highlightedRect == nil ? "Drag across displays · Space: window · E: element · Esc: cancel" : "Drag a new area or press Return · Esc: cancel"
        case .window: return "Click a window · Space: area · Esc: cancel"
        case .fullscreen: return "Click a display to capture · Esc: cancel"
        case .previousArea: return highlightedRect == nil ? "No previous screenshot area · A: area · Esc: cancel" : "Click or press Return to capture the previous area"
        case .element: return highlightedRect == nil ? "No accessible element here · E: area · Esc: cancel" : "Click an element · E: area · Esc: cancel"
        case .scrolling: return "Drag the scrolling capture area · Esc: cancel"
        case .recording: return highlightedRect == nil ? "Drag the area to record · Esc: cancel" : "Choose a recording type or press Return · Esc: cancel"
        case .timer, .text: return "Drag an area · Esc: cancel"
        }
    }

    static var selfTimerSeconds: Int { UpshotPreferences.captureDelaySeconds > 0 ? UpshotPreferences.captureDelaySeconds : 5 }

    var canArmCaptureActions: Bool {
        isAllInOne && [.area, .fullscreen, .window, .element, .previousArea].contains(mode)
    }

    var showsSelectionSize: Bool {
        isAllInOne && mode.drawsArea
    }

    var canEditSelectionSize: Bool {
        isAllInOne && start == nil && mode.drawsArea
    }

    var canRecordSelection: Bool {
        isAllInOne && mode == .recording && start == nil && highlightedRect.map(RecordingAreaGeometry.isLargeEnough) == true
    }

    func chooseRecordingOutput(_ output: RecordingOutputMode, eventTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard isAllInOne, mode == .recording, !completingSelection else { return }
        guard canRecordSelection, let rect = highlightedRect else {
            status = "Drag a larger area to record"
            AppLog.event("recording", "all_in_one_recording_output_rejected", fields: ["mode": output.rawValue, "reason": "no_area_selection"])
            redraw()
            return
        }
        AppLog.event("recording", "all_in_one_recording_output_chosen", fields: ["mode": output.rawValue, "width": String(describing: rect.width), "height": String(describing: rect.height)])
        complete(kind: .recording(output), rect: rect, eventTime: eventTime)
    }

    var selectionPixelSize: CGSize? {
        guard let highlightedRect else { return nil }
        let scale = pixelScale(for: highlightedRect)
        return CGSize(width: (highlightedRect.width * scale).rounded(), height: (highlightedRect.height * scale).rounded())
    }

    private var selectionBounds: CGRect {
        snapshots.reduce(CGRect.null) { $0.union($1.frame) }
    }

    private func pixelScale(for rect: CGRect) -> CGFloat {
        snapshots.filter { $0.frame.intersects(rect) }.map(\.scale).max() ?? snapshots.map(\.scale).max() ?? 1
    }

    func setSelectionPixelSize(width: Int? = nil, height: Int? = nil) {
        guard canEditSelectionSize, let rect = highlightedRect, !completingSelection else { return }
        let scale = pixelScale(for: rect)
        let bounds = selectionBounds
        var size = CGSize(width: width.map { CGFloat(max($0, 1)) / scale } ?? rect.width,
                          height: height.map { CGFloat(max($0, 1)) / scale } ?? rect.height)
        if let aspect {
            if width != nil { size.height = size.width / aspect.ratio } else { size.width = size.height * aspect.ratio }
        }
        size = CGSize(width: min(size.width, bounds.width), height: min(size.height, bounds.height))
        let resized = RecordingAreaGeometry.moved(CGRect(x: rect.minX, y: rect.maxY - size.height, width: size.width, height: size.height), by: .zero, in: bounds)
        highlightedRect = AreaCaptureSnapshot.pixelAlignedRect(resized, snapshots: snapshots)
        if let size = selectionPixelSize { AppLog.event("capture", "all_in_one_selection_size_edited", fields: ["width": String(format: "%.0f", size.width), "height": String(format: "%.0f", size.height)]) }
        redraw()
    }

    func setAspect(_ selected: RecordingAreaAspect?) {
        guard !completingSelection else { return }
        aspect = selected
        if let selected, canEditSelectionSize, let rect = highlightedRect {
            highlightedRect = AreaCaptureSnapshot.pixelAlignedRect(RecordingAreaGeometry.reshaped(rect, to: selected.ratio, in: selectionBounds), snapshots: snapshots)
        }
        AppLog.event("capture", "all_in_one_aspect_ratio_changed", fields: ["aspect": selected?.title ?? "freeform"])
        redraw()
    }

    func restoreKeyboardFocus() {
        guard let view = views.first(where: { $0.window?.isKeyWindow == true }) ?? views.first else { return }
        view.window?.makeFirstResponder(view)
    }

    private func toggleCaptureAction(_ action: AllInOneCaptureMode) {
        guard canArmCaptureActions else { return }
        let armed: Bool
        if action == .timer {
            selfTimerArmed.toggle()
            armed = selfTimerArmed
        } else {
            textRecognitionArmed.toggle()
            armed = textRecognitionArmed
        }
        delaySeconds = selfTimerArmed ? Self.selfTimerSeconds : requestedDelaySeconds
        status = nil
        AppLog.event("capture", "all_in_one_capture_action_changed", fields: ["action": action.rawValue, "armed": String(describing: armed), "delay_seconds": String(describing: delaySeconds), "mode": mode.rawValue])
        if armed, mode == .area || mode == .previousArea, start == nil, let rect = highlightedRect, rect.width >= 1, rect.height >= 1 {
            commitSelection()
            return
        }
        updateWindowStream()
        redraw()
    }

    private func disarmCaptureActions() {
        guard selfTimerArmed || textRecognitionArmed else { return }
        selfTimerArmed = false
        textRecognitionArmed = false
        delaySeconds = requestedDelaySeconds
        AppLog.event("capture", "all_in_one_capture_actions_cleared", fields: ["mode": mode.rawValue])
    }

    func select(smartElement: Bool = false, allInOne: Bool = false, initialMode: AllInOneCaptureMode = .area, scrolling: Bool = false,
                delaySeconds: Int = 0, includeWindowShadow: Bool = false, includeWindowCursor: Bool = true) async throws -> AreaCaptureSelectionResult? {
        guard !active, !CaptureCountdownPresenter.shared.isRunning, !Task.isCancelled else { return nil }
        cursor = ScreenshotCursorService.snapshot()
        active = true
        defer {
            active = false
            snapshots.removeAll()
            windows.removeAll()
            if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
            screenObserver = nil
            DesktopIconVisibilityService.shared.endCapture(desktopIconLease)
            desktopIconLease = nil
            shareableContent = nil
            contentTask = nil
            contentError = nil
            startupTask = nil
            desiredWindowID = nil
            currentWindowID = nil
            completingSelection = false
        }
        cancelled = false
        let sessionID = UUID()
        self.sessionID = sessionID
        selectionError = nil
        self.delaySeconds = delaySeconds
        requestedDelaySeconds = delaySeconds
        selfTimerArmed = false
        textRecognitionArmed = false
        aspect = nil
        self.includeWindowShadow = includeWindowShadow
        windowShowsCursor = includeWindowCursor && UpshotPreferences.screenshotShowCursor
        frozen = UpshotPreferences.areaSelectionFreezeScreen
        isAllInOne = allInOne
        isScrollingOnly = scrolling
        mode = scrolling ? .scrolling : smartElement ? .element : allInOne ? UpshotPreferences.allInOneLastMode : initialMode
        status = nil
        start = nil
        highlightedRect = allInOne ? AreaSelectionMemory.lastSelectionRect : nil
        pointer = NSEvent.mouseLocation
        windows = Self.windowTargets()
        if smartElement && !AreaSelectionAccessibility.hasPermission {
            requestAccessibilityPermission()
            return nil
        }
        if mode == .element && !AreaSelectionAccessibility.hasPermission {
            mode = .area
            requestAccessibilityPermission()
            AppLog.event("capture", "all_in_one_element_mode_unavailable_accessibility_permission_missing", fields: ["fallback_mode": mode.rawValue])
        }
        if mode == .previousArea { highlightedRect = AreaSelectionMemory.previousScreenshotRect }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                AppLog.event("capture", "area_selector_display_layout_changed", fields: ["outcome": "cancelled"])
                self?.cancel()
            }
        }
        do {
            let result = try await withTaskCancellationHandler {
                desktopIconLease = try await DesktopIconVisibilityService.shared.beginCapture(waitForPresentation: false)
                snapshots = try AreaCaptureSnapshot.displayGeometry()
                try Task.checkCancellation()
                guard !cancelled else { return nil as AreaCaptureSelectionResult? }
                return await withCheckedContinuation { continuation in
                    self.continuation = continuation
                    if Task.isCancelled || cancelled { finish(nil); return }
                    showPanels()
                    beginAcquisition()
                }
            } onCancel: {
                Task { @MainActor in
                    if self.sessionID == sessionID { self.cancel() }
                }
            }
            await stopStreams()
            if let selectionError { throw selectionError }
            guard !cancelled && !Task.isCancelled else { return nil }
            if result?.desktopIconLease != nil { desktopIconLease = nil }
            return result
        } catch {
            await stopStreams()
            throw error
        }
    }

    private func loadContent() async throws -> SCShareableContent {
        if let shareableContent { return shareableContent }
        if contentTask == nil {
            contentError = nil
            contentTask = Task { @MainActor in
                do { shareableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) }
                catch { contentError = error }
            }
        }
        if let contentTask { await contentTask.value }
        contentTask = nil
        try Task.checkCancellation()
        if let contentError { throw contentError }
        guard let shareableContent else { throw CocoaError(.fileReadUnknown) }
        return shareableContent
    }

    private func beginAcquisition() {
        startupTask = Task { @MainActor in
            do {
                let content = try await loadContent()
                try Task.checkCancellation()
                if frozen {
                    let captured = try await AreaCaptureSnapshot.captureAll(desktopIconsPrepared: true, content: content)
                    try Task.checkCancellation()
                    guard !cancelled, !completingSelection, continuation != nil else { return }
                    snapshots = captured
                    for view in views {
                        if let snapshot = captured.first(where: { $0.displayID == view.snapshot.displayID }) { view.updateSnapshot(snapshot) }
                    }
                    AppLog.event("capture", "area_selector_frozen_snapshot_ready", fields: ["displays": String(describing: captured.count)])
                } else {
                    await startStreams(content: content)
                }
            } catch {
                if !Task.isCancelled { AppLog.event("capture", "area_selector_acquisition_unavailable", fields: ["error": AppLog.error(error), "fallback": "screenshot"]) }
            }
        }
    }

    private func startStreams(content: SCShareableContent) async {
        for snapshot in snapshots {
            guard !Task.isCancelled, !cancelled, !completingSelection else { return }
            guard let display = content.displays.first(where: { $0.displayID == snapshot.displayID }) else {
                AppLog.event("capture", "area_capture_stream_unavailable", fields: ["display": String(describing: snapshot.displayID), "fallback": "screenshot", "reason": "missing_display"])
                continue
            }
            let stream = AreaCaptureFrameStream(displayID: snapshot.displayID, frame: snapshot.frame, didUpdate: { [weak self] in
                if UpshotPreferences.areaSelectionMagnifier { self?.redraw() }
            }, didFail: { error in
                AppLog.event("capture", "area_capture_stream_unavailable", fields: ["display": String(describing: snapshot.displayID), "error": AppLog.error(error), "fallback": "screenshot"])
            })
            streams.append(stream)
            do { try await stream.start(display: display, content: content) }
            catch { AppLog.event("capture", "area_capture_stream_unavailable", fields: ["display": String(describing: snapshot.displayID), "error": AppLog.error(error), "fallback": "screenshot"]) }
        }
    }

    private func stopStreams() async {
        startupTask?.cancel()
        if let startupTask { await startupTask.value }
        windowStreamTask?.cancel()
        if let windowStreamTask { await windowStreamTask.value }
        selectionTask?.cancel()
        if let selectionTask { await selectionTask.value }
        contentTask?.cancel()
        if let contentTask { await contentTask.value }
        let allStreams = streams + [windowStream].compactMap { $0 }
        guard !allStreams.isEmpty else { return }
        var stopped = 0
        var failed = 0
        for stream in allStreams {
            do { try await stream.stop(); stopped += 1 }
            catch { failed += 1 }
        }
        streams.removeAll()
        windowStream = nil
        AppLog.event("capture", "area_capture_streams_released", fields: ["failed": String(describing: failed), "retained": "0", "stopped": String(describing: stopped)])
    }

    private func requestAccessibilityPermission() {
        AreaSelectionAccessibility.requestPermission()
        CaptureTextFeedbackPresenter.shared.showFailure(title: "Enable Accessibility for smart element capture", displayID: ActiveDisplayResolver.activeDisplayID(preferPointer: true))
    }

    private func showPanels() {
        for snapshot in snapshots {
            let panel = AreaCaptureSelectionPanel(contentRect: snapshot.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isOpaque = frozen && snapshot.isCaptured
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.hidesOnDeactivate = false
            panel.isReleasedWhenClosed = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
            let view = AreaCaptureSelectionView(snapshot: snapshot, frozen: frozen, selector: self)
            panel.contentView = view
            panel.initialFirstResponder = view
            panel.makeFirstResponder(view)
            panels.append(panel)
            views.append(view)
            panel.orderFrontRegardless()
        }
        AreaCaptureWindowFilter.alwaysExcludedWindowIDs.formUnion(panels.map { CGWindowID($0.windowNumber) })
        let panel = panels.first { $0.frame.contains(pointer) } ?? panels.first
        panel?.makeKey()
        panel?.makeFirstResponder(panel?.contentView)
        if highlightedRect == nil { move(to: pointer) } else { redraw() }
        AppLog.event("capture", "area_selector_opened", fields: ["crosshair": String(describing: UpshotPreferences.areaSelectionCrosshair), "displays": String(describing: snapshots.count), "frozen": String(describing: frozen), "magnifier": String(describing: UpshotPreferences.areaSelectionMagnifier)])
        if isAllInOne { AppLog.event("capture", "all_in_one_opened", fields: ["mode": mode.rawValue, "restored_selection": String(describing: highlightedRect != nil)]) }
    }

    func magnifierImage(for snapshot: AreaCaptureSnapshot) -> CGImage? {
        if !frozen { return streams.first { $0.displayID == snapshot.displayID }?.magnifierImage(at: pointer, geometry: snapshot) }
        return snapshot.isCaptured ? snapshot.image.cropping(to: snapshot.magnifierPixelRect(at: pointer)) : nil
    }

    func magnifierSamplePosition(for snapshot: AreaCaptureSnapshot) -> CGPoint {
        snapshot.magnifierSamplePosition(at: pointer)
    }

    func readout(for snapshot: AreaCaptureSnapshot) -> AreaSelectionReadout {
        let pixel = snapshot.pixelPoint(at: pointer)
        var size: String?
        if let highlightedRect, highlightedRect.width >= 1, highlightedRect.height >= 1 {
            let scale = snapshots.filter { $0.frame.intersects(highlightedRect) }.map(\.scale).max() ?? snapshot.scale
            size = "\(Int((highlightedRect.width * scale).rounded())) × \(Int((highlightedRect.height * scale).rounded()))"
        }
        let previewUnavailable = !frozen && UpshotPreferences.areaSelectionMagnifier && !streams.contains(where: { $0.displayID == snapshot.displayID && $0.isReady })
        return AreaSelectionReadout(coordinates: "\(Int(pixel.x)), \(Int(pixel.y))", size: size, note: previewUnavailable ? "Live preview unavailable" : nil)
    }

    func chooseMode(_ selected: AllInOneCaptureMode) {
        guard !completingSelection else { return }
        guard !isScrollingOnly else { return }
        guard isAllInOne || [.area, .window, .element].contains(selected) else { return }
        if selected.isCaptureAction {
            toggleCaptureAction(selected)
            return
        }
        if selected == .scrolling || selected == .recording { disarmCaptureActions() }
        if selected == .element && !AreaSelectionAccessibility.hasPermission {
            finish(nil)
            requestAccessibilityPermission()
            return
        }
        mode = selected
        status = nil
        start = nil
        highlightedRect = selected == .previousArea ? AreaSelectionMemory.previousScreenshotRect : nil
        if selected.drawsArea { highlightedRect = AreaSelectionMemory.lastSelectionRect }
        move(to: NSEvent.mouseLocation)
        AppLog.event("capture", "area_selection_mode_changed", fields: ["mode": mode.rawValue])
        if selected == .previousArea { commitSelection() }
    }

    func move(to point: CGPoint) {
        guard !completingSelection else { return }
        pointer = point
        if let start {
            let rect: CGRect
            if let aspect, mode.drawsArea {
                rect = RecordingAreaGeometry.drawn(from: start, to: point, ratio: aspect.ratio, fromCenter: false, in: selectionBounds)
            } else {
                rect = CGRect(x: min(start.x, point.x), y: min(start.y, point.y), width: abs(point.x - start.x), height: abs(point.y - start.y))
            }
            highlightedRect = AreaCaptureSnapshot.pixelAlignedRect(rect, snapshots: snapshots)
        } else {
            switch mode {
            case .element:
                hoveredWindow = windows.first { $0.frame.contains(point) }
                highlightedRect = hoveredWindow.flatMap { AreaSelectionAccessibility.frame(at: point, processID: $0.processID) }.map { AreaCaptureSnapshot.pixelAlignedRect($0, snapshots: snapshots) }
            case .window:
                hoveredWindow = windows.first { $0.frame.contains(point) }
                highlightedRect = hoveredWindow?.frame
            case .fullscreen:
                highlightedRect = snapshots.first { $0.frame.contains(point) }?.frame
            case .area, .previousArea, .scrolling, .recording, .timer, .text: break
            }
        }
        updateWindowStream()
        redraw()
    }

    private func updateWindowStream() {
        desiredWindowID = mode == .window && delaySeconds == 0 ? hoveredWindow?.id : nil
        guard windowStreamTask == nil, currentWindowID != desiredWindowID else { return }
        windowStreamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { windowStreamTask = nil }
            while !Task.isCancelled && !cancelled && !completingSelection && currentWindowID != desiredWindowID {
                if let windowStream { try? await windowStream.stop() }
                windowStream = nil
                let targetID = desiredWindowID
                currentWindowID = targetID
                guard let targetID else { break }
                do {
                    let content = try await loadContent()
                    try Task.checkCancellation()
                    guard !completingSelection, let window = content.windows.first(where: { $0.windowID == targetID }),
                          let target = windows.first(where: { $0.id == targetID }) else { continue }
                    let displayID = snapshots.first { $0.frame.intersects(target.frame) }?.displayID ?? 0
                    let source = AreaCaptureFrameStream(displayID: displayID, frame: target.frame, didUpdate: {}, didFail: { error in
                        AppLog.event("capture", "area_window_stream_unavailable", fields: ["error": AppLog.error(error), "window": String(describing: targetID)])
                    })
                    windowStream = source
                    try await source.start(window: window, includeShadow: includeWindowShadow, showsCursor: windowShowsCursor)
                } catch {
                    AppLog.event("capture", "area_window_stream_unavailable", fields: ["error": AppLog.error(error), "window": String(describing: targetID)])
                    if let windowStream { try? await windowStream.stop() }
                    windowStream = nil
                }
            }
        }
    }

    func mouseDown(at point: CGPoint) {
        move(to: point)
        guard mode.drawsArea else { return }
        start = point
        highlightedRect = nil
        if mode == .recording { status = nil }
        redraw()
    }

    func mouseUp(at point: CGPoint, eventTime: TimeInterval) {
        move(to: point)
        commitSelection(eventTime: eventTime)
    }

    private func commitSelection(eventTime: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        if mode == .recording {
            start = nil
            if let rect = highlightedRect, !RecordingAreaGeometry.isLargeEnough(rect) { highlightedRect = nil }
            redraw()
            return
        }
        guard let rect = highlightedRect, rect.width >= 1, rect.height >= 1 else {
            start = nil
            if mode == .previousArea { status = "No previous screenshot area" }
            redraw()
            return
        }
        switch mode {
        case .area, .previousArea: complete(kind: .area, rect: rect, eventTime: eventTime)
        case .element:
            AppLog.event("capture", "smart_element_selected", fields: ["height": String(format: "%.1f", rect.height), "width": String(format: "%.1f", rect.width), "x": String(format: "%.1f", rect.minX), "y": String(format: "%.1f", rect.minY)])
            complete(kind: .element, rect: rect, eventTime: eventTime)
        case .window:
            if let hoveredWindow { complete(kind: .window(hoveredWindow.id), rect: rect, eventTime: eventTime) }
        case .fullscreen:
            if let displayID = snapshots.first(where: { $0.frame == rect })?.displayID { complete(kind: .fullscreen(displayID), rect: rect, eventTime: eventTime) }
        case .scrolling: complete(kind: .scrolling, rect: rect, eventTime: eventTime)
        case .recording, .timer, .text: break
        }
    }

    func cancel() { cancelled = true; finish(nil) }

    func toggleCrosshair() {
        UpshotPreferences.areaSelectionCrosshair.toggle()
        AppLog.event("capture", "area_crosshair_changed", fields: ["enabled": String(describing: UpshotPreferences.areaSelectionCrosshair)])
        redraw()
    }

    func toggleMagnifier() {
        UpshotPreferences.areaSelectionMagnifier.toggle()
        AppLog.event("capture", "area_magnifier_changed", fields: ["enabled": String(describing: UpshotPreferences.areaSelectionMagnifier)])
        redraw()
    }

    func keyDown(_ event: NSEvent) {
        if completingSelection {
            if event.keyCode == 53 { cancel() }
            return
        }
        if let character = event.charactersIgnoringModifiers?.lowercased() {
            if isAllInOne, let selected = AllInOneCaptureMode.allCases.first(where: { $0.shortcut == character }) {
                chooseMode(selected)
                return
            }
            switch character {
            case "a": chooseMode(.area); return
            case "e": chooseMode(mode == .element ? .area : .element); return
            case "x":
                toggleCrosshair()
                return
            case "m":
                toggleMagnifier()
                return
            default: break
            }
        }
        switch event.keyCode {
        case 53: cancel()
        case 49: chooseMode(mode == .window ? .area : .window)
        case 36 where isAllInOne && mode == .recording, 76 where isAllInOne && mode == .recording:
            chooseRecordingOutput(.forReturnKey(modifierFlags: event.modifierFlags), eventTime: event.timestamp)
        case 36, 76: commitSelection(eventTime: event.timestamp)
        default: break
        }
    }

    private func complete(kind: AreaCaptureSelectionResult.Kind, rect: CGRect, eventTime: TimeInterval) {
        guard !completingSelection else { return }
        completingSelection = true
        startupTask?.cancel()
        AppLog.event("capture", "area_selector_selected", fields: ["height": String(format: "%.1f", rect.height), "mode": mode.rawValue, "width": String(format: "%.1f", rect.width), "x": String(format: "%.1f", rect.minX), "y": String(format: "%.1f", rect.minY)])
        let target: WindowTarget?
        if case .window(let id) = kind {
            target = windows.first { $0.id == id }
        } else {
            target = Self.target(in: rect, windows: windows)
        }
        if isAllInOne { AreaSelectionMemory.rememberSelection(mode: mode, rect: rect) }
        let location = ActiveDisplayResolver.quartzPoint(fromAppKit: pointer)
        let captureCursor = cursor.map {
            ScreenshotCursorSnapshot(image: $0.image, pointSize: $0.pointSize, hotSpot: $0.hotSpot, location: location)
        }
        var result = AreaCaptureSelectionResult(kind: kind, rect: rect, snapshots: snapshots, frozen: frozen, source: target?.source, cursor: captureCursor)
        result.skipBackgroundPreset = NSEvent.modifierFlags.contains(.shift)
        result.selectionTime = eventTime
        result.capturedAt = Date(timeIntervalSinceNow: eventTime - ProcessInfo.processInfo.systemUptime)
        result.windowIncludesShadow = includeWindowShadow
        result.windowShowsCursor = windowShowsCursor
        result.delaySeconds = delaySeconds
        result.recognizesText = textRecognitionArmed
        if selfTimerArmed || textRecognitionArmed { AppLog.event("capture", "all_in_one_capture_actions_applied", fields: ["capture_text": String(describing: textRecognitionArmed), "delay_seconds": String(describing: delaySeconds), "self_timer": String(describing: selfTimerArmed)]) }
        if case .window(let windowID) = kind, delaySeconds == 0 {
            completeWindowSelection(result, windowID: windowID, eventTime: eventTime)
            return
        }
        switch kind {
        case .scrolling, .recording: break
        default:
            if delaySeconds == 0 {
                completeDisplaySelection(result, eventTime: eventTime)
                return
            } else {
                result.desktopIconLease = desktopIconLease
            }
        }
        finish(result)
    }

    private func completeWindowSelection(_ result: AreaCaptureSelectionResult, windowID: CGWindowID, eventTime: TimeInterval) {
        completingSelection = true
        var selected = result
        if let windowStream, windowStream.windowID == windowID, windowStream.isReady,
           let snapshot = try? windowStream.windowSnapshot(for: eventTime) {
            selected.composedImage = snapshot.image
            selected.composedImageScale = snapshot.scale
            snapshot.logTiming(windowID: windowID, shadow: includeWindowShadow, eventTime: eventTime, acquisition: "window-stream")
            finish(selected)
            return
        }
        selectionTask = Task { @MainActor in
            defer { selectionTask = nil }
            do {
                let content = try await loadContent()
                try Task.checkCancellation()
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else { throw CocoaError(.fileReadUnknown) }
                let snapshot = try await AreaCaptureWindowSnapshot.capture(window: window, includeShadow: includeWindowShadow,
                                                                          showsCursor: windowShowsCursor, eventTime: eventTime)
                try Task.checkCancellation()
                guard !cancelled, continuation != nil else { return }
                selected.composedImage = snapshot.image
                selected.composedImageScale = snapshot.scale
                snapshot.logTiming(windowID: windowID, shadow: includeWindowShadow, eventTime: eventTime, acquisition: "window-screenshot")
                finish(selected)
            } catch {
                if !cancelled { selectionError = error }
                finish(nil)
            }
        }
    }

    private func completeDisplaySelection(_ result: AreaCaptureSelectionResult, eventTime: TimeInterval) {
        var retained: [CGDirectDisplayID: AreaCaptureSnapshot] = [:]
        for geometry in result.snapshots where geometry.frame.intersects(result.rect) {
            if frozen && geometry.isCaptured && (geometry.presentationTime.map { $0 <= eventTime } ?? true) { retained[geometry.displayID] = geometry }
            else if !frozen, let source = streams.first(where: { $0.displayID == geometry.displayID && $0.isReady }),
                    let snapshot = try? source.snapshot(for: eventTime) { retained[geometry.displayID] = snapshot }
        }
        let participating = result.snapshots.filter { $0.frame.intersects(result.rect) }
        if retained.count == participating.count && !participating.isEmpty {
            var selected = result
            do {
                selected.snapshots = participating.compactMap { retained[$0.displayID] }
                selected.composedImage = try AreaCaptureSnapshot.composite(selected.snapshots, in: result.rect)
                selected.logTiming(composedAt: ProcessInfo.processInfo.systemUptime, acquisition: frozen ? "frozen" : "stream")
                finish(selected)
            } catch {
                selectionError = error
                finish(nil)
            }
            return
        }
        selectionTask = Task { @MainActor in
            defer { selectionTask = nil }
            do {
                let content = try await loadContent()
                var selected = result
                selected.snapshots = try await AreaCaptureSnapshot.acquireSelection(result.snapshots, in: result.rect, retained: retained) { geometry, rect in
                    AppLog.event("capture", "area_capture_screenshot_fallback_requested", fields: ["display": String(describing: geometry.displayID), "reason": "missing_frame", "selection_to_request_ms": String(format: "%.3f", (ProcessInfo.processInfo.systemUptime - eventTime) * 1000)])
                    return try await AreaCaptureSnapshot.capture(geometry, in: rect, content: content)
                }
                try Task.checkCancellation()
                guard !cancelled, continuation != nil else { return }
                selected.composedImage = try AreaCaptureSnapshot.composite(selected.snapshots, in: result.rect)
                selected.logTiming(composedAt: ProcessInfo.processInfo.systemUptime, acquisition: "screenshot-fallback")
                finish(selected)
            } catch {
                if !cancelled { selectionError = error }
                finish(nil)
            }
        }
    }

    static func captureSource(in rect: CGRect) -> CaptureSource? {
        target(in: rect, windows: windowTargets())?.source
    }

    private static func target(in rect: CGRect, windows: [WindowTarget]) -> WindowTarget? {
        windows.first { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) }
            ?? windows.filter { $0.frame.intersects(rect) }.max {
                let left = $0.frame.intersection(rect)
                let right = $1.frame.intersection(rect)
                return left.width * left.height < right.width * right.height
            }
    }

    private func redraw() {
        for view in views { view.needsDisplay = true }
    }

    private func finish(_ result: AreaCaptureSelectionResult?) {
        guard let continuation else { return }
        self.continuation = nil
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        AreaCaptureWindowFilter.alwaysExcludedWindowIDs.subtract(panels.map { CGWindowID($0.windowNumber) })
        for panel in panels { panel.orderOut(nil) }
        panels.removeAll()
        views.removeAll()
        snapshots.removeAll()
        windows.removeAll()
        AppLog.event("capture", "area_selector_closed", fields: ["cancelled": String(describing: result == nil)])
        continuation.resume(returning: result)
    }

    private static func windowTargets() -> [WindowTarget] {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard (window[kCGWindowLayer as String] as? Int) == 0,
                  (window[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let processID = window[kCGWindowOwnerPID as String] as? pid_t,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CaptureRectangleDecoder.decode(bounds), frame.width > 1, frame.height > 1 else { return nil }
            let application = NSRunningApplication(processIdentifier: processID)
            let source = CaptureSource(bundleIdentifier: application?.bundleIdentifier,
                                       appName: application?.localizedName ?? window[kCGWindowOwnerName as String] as? String ?? "Unknown",
                                       windowTitle: window[kCGWindowName as String] as? String)
            return WindowTarget(id: id, processID: processID, frame: ActiveDisplayResolver.appKitRect(fromQuartz: frame), source: source)
        }
    }
}

private final class AreaCaptureSelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AreaCaptureSelectionView: NSView {
    private(set) var snapshot: AreaCaptureSnapshot
    let frozen: Bool
    unowned let selector: AreaCaptureSelection
    private var tracking: NSTrackingArea?

    init(snapshot: AreaCaptureSnapshot, frozen: Bool, selector: AreaCaptureSelection) {
        self.snapshot = snapshot
        self.frozen = frozen
        self.selector = selector
        super.init(frame: CGRect(origin: .zero, size: snapshot.frame.size))
        let overlay: NSView
        if selector.isAllInOne {
            overlay = NSHostingView(rootView: AllInOneCaptureToolbar(selector: selector, stacksSizeFields: snapshot.frame.width < AllInOneCaptureToolbar.singleRowMinimumWidth))
        } else {
            overlay = AreaCaptureInstructionHostingView(rootView: AreaCaptureInstructionHint(selector: selector))
        }
        overlay.translatesAutoresizingMaskIntoConstraints = false
        addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.centerXAnchor.constraint(equalTo: centerXAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -AllInOneCaptureToolbar.bottomInset)
        ])
    }

    required init?(coder: NSCoder) { nil }
    override var acceptsFirstResponder: Bool { true }
    override var isOpaque: Bool { frozen && snapshot.isCaptured }
    func updateSnapshot(_ snapshot: AreaCaptureSnapshot) {
        self.snapshot = snapshot
        window?.isOpaque = frozen && snapshot.isCaptured
        needsDisplay = true
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: .zero, options: [.activeAlways, .mouseMoved, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        self.tracking = tracking
    }

    private func globalPoint(_ event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func keyDown(with event: NSEvent) { selector.keyDown(event) }
    override func mouseMoved(with event: NSEvent) { selector.move(to: globalPoint(event)) }
    override func mouseDragged(with event: NSEvent) { selector.move(to: globalPoint(event)) }
    override func mouseDown(with event: NSEvent) {
        window?.makeKey()
        window?.makeFirstResponder(self)
        selector.mouseDown(at: globalPoint(event))
    }
    override func mouseUp(with event: NSEvent) { selector.mouseUp(at: globalPoint(event), eventTime: event.timestamp) }
    override func rightMouseDown(with event: NSEvent) { selector.cancel() }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.clear(bounds)
        if frozen && snapshot.isCaptured { context.draw(snapshot.image, in: bounds) }
        let selected = selector.highlightedRect?.offsetBy(dx: -snapshot.frame.minX, dy: -snapshot.frame.minY)
        let dimming = NSBezierPath(rect: bounds)
        if let selected {
            let intersection = selected.intersection(bounds)
            if !intersection.isNull && !intersection.isEmpty { dimming.appendRect(intersection) }
        }
        dimming.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.3).setFill()
        dimming.fill()
        if let selected {
            AreaSelectionMagnifier.drawSelectionBorder(in: context, rect: selected)
        }
        if snapshot.frame.contains(selector.pointer) {
            let point = CGPoint(x: selector.pointer.x - snapshot.frame.minX, y: selector.pointer.y - snapshot.frame.minY)
            AreaSelectionMagnifier.draw(in: context, bounds: bounds, point: point, selection: selected,
                                        image: selector.magnifierImage(for: snapshot), samplePosition: selector.magnifierSamplePosition(for: snapshot), readout: selector.readout(for: snapshot),
                                        showsCrosshair: UpshotPreferences.areaSelectionCrosshair,
                                        showsMagnifier: UpshotPreferences.areaSelectionMagnifier)
        }
    }
}

private final class AreaCaptureInstructionHostingView: NSHostingView<AreaCaptureInstructionHint> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

extension AreaCaptureSelection {
    static func renderView(image: CGImage, mode: AllInOneCaptureMode, allInOne: Bool, crosshair: Bool, size: CGSize = CGSize(width: 1000, height: 625),
                           aspect: RecordingAreaAspect? = nil, status: String? = nil,
                           pointer: CGPoint? = nil, selection: CGRect? = nil) -> NSView {
        precondition(UpshotStorage.isRenderingStates)
        let selector = AreaCaptureSelection.shared
        let snapshot = AreaCaptureSnapshot(displayID: 0, frame: CGRect(origin: .zero, size: size), image: image)
        selector.snapshots = [snapshot]
        selector.frozen = true
        selector.isAllInOne = allInOne
        selector.selfTimerArmed = mode == .timer
        selector.textRecognitionArmed = mode == .text
        selector.mode = mode == .timer ? .window : mode == .text ? .area : mode
        selector.aspect = aspect
        selector.status = status
        selector.start = nil
        selector.pointer = pointer ?? CGPoint(x: (size.width * 0.65).rounded(), y: (size.height * 0.592).rounded())
        let selection = selection ?? CGRect(x: size.width * 0.12, y: size.height * 0.28, width: size.width * 0.62, height: size.height * 0.528)
        selector.highlightedRect = crosshair || mode == .text ? nil : aspect.map { RecordingAreaGeometry.reshaped(selection, to: $0.ratio, in: snapshot.frame) } ?? selection
        return AreaCaptureSelectionView(snapshot: snapshot, frozen: true, selector: selector)
    }
}
