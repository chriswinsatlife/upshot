import AppKit
import AVFoundation
import CoreMedia
import Observation
import QuartzCore
import SwiftUI

@MainActor
@Observable
final class StudioWallpaperVideoPlayback {
    let player = AVPlayer()
    private var duration: TimeInterval = 0
    private var previousTime: TimeInterval?
    private var isSeeking = false
    private var seekGeneration = UUID()
    private var pendingSynchronization: (time: TimeInterval, isPlaying: Bool)?

    func load(_ url: URL) async {
        stop()
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration).seconds
            guard !Task.isCancelled else { return }
            guard duration.isFinite, duration > 0 else { throw StudioWallpaperError.unreadableMedia }
            self.duration = duration
            player.isMuted = true
            player.actionAtItemEnd = .pause
            player.replaceCurrentItem(with: AVPlayerItem(asset: asset))
        } catch {
            AppLog.event("rendering", "studio_wallpaper_preview_failed", fields: ["error": AppLog.error(error)])
        }
    }

    func synchronize(time: TimeInterval, isPlaying: Bool) {
        guard duration > 0, time.isFinite else { return }
        if isSeeking {
            pendingSynchronization = (time, isPlaying)
            if !isPlaying { player.pause() }
            return
        }
        let target = max(0, time).truncatingRemainder(dividingBy: duration)
        let current = player.currentTime().seconds
        let drift = target - (current.isFinite ? current : 0)
        let jumped = previousTime.map { abs(time - $0) > 0.25 } ?? true
        previousTime = time
        if !isPlaying { player.pause() }
        if !isSeeking, jumped || abs(drift) > (isPlaying ? 0.35 : 0.01) {
            isSeeking = true
            let generation = seekGeneration
            player.seek(to: CMTime(seconds: target, preferredTimescale: 60_000), toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.seekGeneration == generation else { return }
                    self.isSeeking = false
                    if let pending = self.pendingSynchronization {
                        self.pendingSynchronization = nil
                        self.synchronize(time: pending.time, isPlaying: pending.isPlaying)
                    }
                }
            }
        }
        if isPlaying {
            let adjustment = abs(drift) <= 0.02 ? 0 : min(0.12, max(-0.12, drift / 1.5))
            player.playImmediately(atRate: Float(max(0.1, 1 + adjustment)))
        }
    }

    func stop() {
        seekGeneration = UUID()
        pendingSynchronization = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        duration = 0
        previousTime = nil
        isSeeking = false
    }
}

struct StudioWallpaperVideoView: View {
    let url: URL
    let time: TimeInterval
    let isPlaying: Bool
    @State private var playback = StudioWallpaperVideoPlayback()

    var body: some View {
        StudioWallpaperPlayerLayer(player: playback.player)
            .task(id: url) {
                await playback.load(url)
                playback.synchronize(time: time, isPlaying: isPlaying)
            }
            .onChange(of: time) { _, time in playback.synchronize(time: time, isPlaying: isPlaying) }
            .onChange(of: isPlaying) { _, playing in playback.synchronize(time: time, isPlaying: playing) }
            .onDisappear { playback.stop() }
    }
}

struct StudioWallpaperVideoTile: View {
    let url: URL
    @State private var playback = StudioWallpaperVideoPlayback()
    @State private var isHovering = false

    var body: some View {
        StudioWallpaperPlayerLayer(player: playback.player)
            .task(id: url) {
                await playback.load(url)
                playback.synchronize(time: 0, isPlaying: false)
                if isHovering { playback.player.play() }
            }
            .onHover { hovering in
                isHovering = hovering
                if hovering { playback.player.play() }
                else {
                    playback.player.pause()
                    playback.player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
                }
            }
            .onDisappear { playback.stop() }
    }
}

private struct StudioWallpaperPlayerLayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> StudioWallpaperPlayerContainer {
        let view = StudioWallpaperPlayerContainer()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: StudioWallpaperPlayerContainer, context: Context) {
        view.playerLayer.player = player
    }

    static func dismantleNSView(_ view: StudioWallpaperPlayerContainer, coordinator: ()) {
        view.playerLayer.player = nil
    }
}

private final class StudioWallpaperPlayerContainer: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { return nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
