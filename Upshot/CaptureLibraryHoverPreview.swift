import AppKit
import AVFoundation
import CoreGraphics
import CoreVideo
import QuartzCore
import SwiftUI

struct CaptureLibraryHoverPreview: NSViewRepresentable {
    let session: RecordingSession
    let revision: String
    let hovering: Bool
    let selected: Bool
    let reduceMotion: Bool

    func makeNSView(context: Context) -> CaptureLibraryHoverPreviewView {
        CaptureLibraryHoverPreviewView()
    }

    func updateNSView(_ view: CaptureLibraryHoverPreviewView, context: Context) {
        view.configure(session: session, revision: revision, hovering: hovering, selected: selected, reduceMotion: reduceMotion)
    }

    static func dismantleNSView(_ view: CaptureLibraryHoverPreviewView, coordinator: ()) {
        view.clear()
    }
}

final class CaptureLibraryHoverPreviewView: NSView {
    static let keyboardFocusChangedNotification = Notification.Name("CaptureLibraryKeyboardFocusChanged")
    private var session: RecordingSession?
    private var revision = ""
    private var hovering = false
    private var selected = false
    private var reduceMotion = false
    private var requested = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        center.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.didMiniaturizeNotification, object: nil)
        center.addObserver(self, selector: #selector(visibilityChanged), name: NSWindow.willCloseNotification, object: nil)
        center.addObserver(self, selector: #selector(visibilityChanged), name: NSApplication.didResignActiveNotification, object: nil)
        center.addObserver(self, selector: #selector(visibilityChanged), name: NSView.boundsDidChangeNotification, object: nil)
        center.addObserver(self, selector: #selector(keyboardFocusChanged), name: Self.keyboardFocusChangedNotification, object: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { clear() }
        else {
            enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
            updateRequest()
        }
    }

    func configure(session: RecordingSession, revision: String, hovering: Bool, selected: Bool, reduceMotion: Bool) {
        let hoverChanged = self.hovering != hovering
        if self.session != session || self.revision != revision {
            clear()
        }
        self.session = session
        self.revision = revision
        self.hovering = hovering
        self.selected = selected
        self.reduceMotion = reduceMotion
        if hoverChanged {
            requested = !reduceMotion && (hovering || selected)
            if hovering, !reduceMotion {
                CaptureLibraryHoverPlayback.shared.request(owner: self, session: session)
            } else {
                CaptureLibraryHoverPlayback.shared.stop(owner: self, reason: "mouse_exited")
            }
        } else {
            updateRequest()
        }
    }

    var isEligible: Bool {
        guard !reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              NSApp.isActive, let window, window.isVisible,
              !window.isMiniaturized, window.occlusionState.contains(.visible),
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else { return false }
        if hovering { return true }
        return selected && window.firstResponder is LibraryCollectionView
    }

    func present(_ image: CGImage?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contents = image
        CATransaction.commit()
    }

    func clear() {
        CaptureLibraryHoverPlayback.shared.stop(owner: self, reason: "card_removed")
        requested = false
        present(nil)
    }

    private func updateRequest() {
        let active = !reduceMotion && (hovering || selected)
        guard active != requested else { return }
        requested = active
        if active, let session {
            CaptureLibraryHoverPlayback.shared.request(owner: self, session: session)
        } else {
            CaptureLibraryHoverPlayback.shared.stop(owner: self, reason: "activation_ended")
        }
    }

    @objc private func visibilityChanged(_ notification: Notification) {
        if notification.name == NSWindow.willCloseNotification,
           let closingWindow = notification.object as? NSWindow, closingWindow === window {
            CaptureLibraryHoverPlayback.shared.stop(owner: self, reason: "window_closed")
        } else if !isEligible {
            CaptureLibraryHoverPlayback.shared.stop(owner: self, reason: "visibility_changed")
        }
    }

    @objc private func keyboardFocusChanged(_ notification: Notification) {
        guard let collection = notification.object as? LibraryCollectionView, collection.window === window else { return }
        Task { @MainActor [weak self] in
            guard let self, !self.hovering else { return }
            if self.selected, self.isEligible, let session = self.session {
                CaptureLibraryHoverPlayback.shared.request(owner: self, session: session)
            } else {
                CaptureLibraryHoverPlayback.shared.stop(owner: self, reason: "keyboard_focus_ended")
            }
        }
    }
}

@MainActor
final class CaptureLibraryHoverPlayback {
    static let shared = CaptureLibraryHoverPlayback()
    private weak var owner: CaptureLibraryHoverPreviewView?
    private var playbackTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var renderer: RecordingProjectPreviewRenderer?
    private var player: AVPlayer?
    private var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var boundaryObserver: Any?
    private var requestID: UUID?
    private var sessionID: String?
    private var displayedFrames = 0

    func request(owner: CaptureLibraryHoverPreviewView, session: RecordingSession) {
        stop(reason: "another_card")
        self.owner = owner
        let id = UUID()
        requestID = id
        sessionID = AppLog.identifier(session.directoryURL.path)
        playbackTask = Task { [weak self, weak owner] in
            do {
                try await Task.sleep(for: .milliseconds(300))
                guard let self, let owner, self.requestID == id, owner.isEligible else {
                    self?.stopIfCurrent(id, reason: "activation_unavailable")
                    return
                }
                self.deadlineTask = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                    self?.stopIfCurrent(id, reason: "timeout")
                }
                try await self.play(session: session, owner: owner, requestID: id)
            } catch is CancellationError {
                self?.stopIfCurrent(id, reason: "cancelled")
            } catch {
                AppLog.event("library", "hover_preview_failed", fields: [
                    "item": AppLog.identifier(session.directoryURL.path), "error": AppLog.error(error)
                ])
                self?.stopIfCurrent(id, reason: "error")
            }
        }
    }

    func stop(owner: CaptureLibraryHoverPreviewView, reason: String) {
        guard self.owner === owner else { return }
        stop(reason: reason)
    }

    private func stopIfCurrent(_ id: UUID, reason: String) {
        guard requestID == id else { return }
        stop(reason: reason)
    }

    private func stop(reason: String) {
        guard requestID != nil else { return }
        requestID = nil
        playbackTask?.cancel()
        playbackTask = nil
        deadlineTask?.cancel()
        deadlineTask = nil
        player?.pause()
        if let boundaryObserver { player?.removeTimeObserver(boundaryObserver) }
        boundaryObserver = nil
        item?.cancelPendingSeeks()
        if let item, let output { item.remove(output) }
        player?.replaceCurrentItem(with: nil)
        player = nil
        item = nil
        output = nil
        if let renderer { Task { await renderer.cancel() } }
        renderer = nil
        owner?.present(nil)
        owner = nil
        AppLog.event("library", "hover_preview_stopped", fields: [
            "item": sessionID ?? "", "reason": reason, "frames": String(displayedFrames)
        ])
        displayedFrames = 0
        sessionID = nil
    }

    private func play(session: RecordingSession, owner: CaptureLibraryHoverPreviewView, requestID id: UUID) async throws {
        let configuration = try await RecordingSessionRenderer.makeConfiguration(for: session)
        try Task.checkCancellation()
        let source = AVURLAsset(url: configuration.screenURL)
        let duration = try await source.load(.duration).seconds
        let tracks = try await source.loadTracks(withMediaType: .video)
        let asset = try RecordingCompositionBuilder.makeAsset(
            from: source, tracks: tracks, timeline: configuration.clipTimeline, sourceDuration: duration
        )
        let cameraDuration = if let url = configuration.cameraURL {
            try await AVURLAsset(url: url).load(.duration).seconds
        } else { 0.0 }
        try Task.checkCancellation()
        guard requestID == id, owner.isEligible else { stopIfCurrent(id, reason: "visibility_changed"); return }
        let renderer = try RecordingProjectPreviewRenderer(configuration: configuration, cameraDuration: cameraDuration)
        self.renderer = renderer
        let firstFrame = try await withTaskCancellationHandler {
            try await renderer.firstFrame()
        } onCancel: { Task { await renderer.cancel() } }
        try Task.checkCancellation()
        guard requestID == id, owner.isEligible else { stopIfCurrent(id, reason: "visibility_changed"); return }
        let item = AVPlayerItem(asset: asset)
        let limit = min(5, configuration.clipTimeline.duration)
        item.forwardPlaybackEndTime = CMTime(seconds: limit, preferredTimescale: 600)
        item.preferredMaximumResolution = CGSize(width: 1280, height: 1280)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()
        ])
        output.suppressesPlayerRendering = true
        item.add(output)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.volume = 0
        player.actionAtItemEnd = .pause
        self.player = player
        self.item = item
        self.output = output
        boundaryObserver = player.addBoundaryTimeObserver(
            forTimes: [NSValue(time: CMTime(seconds: max(0, limit - 1 / 600), preferredTimescale: 600))],
            queue: .main
        ) { [weak self] in
            Task { @MainActor in self?.stopIfCurrent(id, reason: "completed") }
        }
        owner.present(firstFrame)
        displayedFrames = 1
        AppLog.event("library", "hover_preview_started", fields: [
            "item": sessionID ?? "", "duration": String(limit), "muted": "true"
        ])
        player.play()
        while !Task.isCancelled, requestID == id {
            guard owner.isEligible else { stopIfCurrent(id, reason: "visibility_changed"); return }
            if item.status == .failed {
                throw item.error ?? RecordingStudioExporter.ExportError.noVideoTrack
            }
            let time = player.currentTime()
            let seconds = time.seconds
            if seconds.isFinite, seconds >= limit - 1 / 600 {
                stopIfCurrent(id, reason: "completed")
                return
            }
            if seconds.isFinite, seconds >= 0, output.hasNewPixelBuffer(forItemTime: time),
               let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
                let image = try await renderer.render(screenFrame: CVReadOnlyPixelBuffer(unsafeBuffer: buffer), editorTime: seconds)
                try Task.checkCancellation()
                guard requestID == id, owner.isEligible else { stopIfCurrent(id, reason: "visibility_changed"); return }
                owner.present(image)
                displayedFrames += 1
            }
            try await Task.sleep(for: .milliseconds(33))
        }
    }
}
