import AppKit
import AVFoundation
import CoreImage
import CoreVideo
import QuartzCore
import SwiftUI

nonisolated struct StudioCameraBubblePreviewParameters: Equatable, Sendable {
    var radius: CGFloat
    var squircle: CGFloat
    var canvasWidth: CGFloat
    var crop: CGRect
}

struct StudioCameraBubbleSoftBlurView: NSViewRepresentable {
    let player: AVPlayer
    let parameters: StudioCameraBubblePreviewParameters

    func makeNSView(context: Context) -> StudioCameraBubblePreviewLayerView {
        let view = StudioCameraBubblePreviewLayerView()
        view.update(player: player, parameters: parameters)
        return view
    }

    func updateNSView(_ view: StudioCameraBubblePreviewLayerView, context: Context) {
        view.update(player: player, parameters: parameters)
    }

    static func dismantleNSView(_ view: StudioCameraBubblePreviewLayerView, coordinator: ()) {
        view.stop()
    }
}

final class StudioCameraBubblePreviewLayerView: NSView, AVPlayerItemOutputPullDelegate {
    private var player: AVPlayer?
    private weak var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var displayLink: CADisplayLink?
    private var lastBuffer: CVPixelBuffer?
    private var renderedBuffer: CVPixelBuffer?
    private var renderedSize: CGSize = .zero
    private var renderedParameters: StudioCameraBubblePreviewParameters?
    private var parameters = StudioCameraBubblePreviewParameters(radius: 0, squircle: 0, canvasWidth: 1920, crop: RecordingCameraCropGeometry.unit)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var idleTicks = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resize
        layer?.isOpaque = false
    }

    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    func update(player: AVPlayer, parameters: StudioCameraBubblePreviewParameters) {
        let changed = self.parameters != parameters
        self.parameters = parameters
        self.player = player
        if item !== player.currentItem { attachOutput() }
        if changed { redraw() }
        wake()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        guard window != nil else { return }
        let link = displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        redraw()
    }

    override func layout() {
        super.layout()
        redraw()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        redraw()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        detachOutput()
        lastBuffer = nil
        renderedBuffer = nil
    }

    private func attachOutput() {
        detachOutput()
        lastBuffer = nil
        renderedBuffer = nil
        layer?.contents = nil
        guard let player, let item = player.currentItem else { return }
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ])
        output.setDelegate(self, queue: .main)
        item.add(output)
        self.item = item
        self.output = output
        if player.rate == 0 {
            player.seek(to: player.currentTime(), toleranceBefore: .zero, toleranceAfter: .zero)
        }
        wake()
    }

    private func detachOutput() {
        if let item, let output { item.remove(output) }
        item = nil
        output = nil
    }

    private func wake() {
        idleTicks = 0
        displayLink?.isPaused = false
    }

    @objc private func tick(_ link: CADisplayLink) {
        if item !== player?.currentItem { attachOutput() }
        guard let output else { return }
        let time = output.itemTime(forHostTime: link.targetTimestamp)
        if output.hasNewPixelBuffer(forItemTime: time),
           let buffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) {
            lastBuffer = buffer
            idleTicks = 0
            redraw()
        } else {
            idleTicks += 1
            if idleTicks > 30, (player?.rate ?? 0) == 0 {
                link.isPaused = true
                output.requestNotificationOfMediaDataChange(withAdvanceInterval: 0.1)
            }
        }
    }

    nonisolated func outputMediaDataWillChange(_ sender: AVPlayerItemOutput) {
        MainActor.assumeIsolated { wake() }
    }

    private func redraw() {
        guard let buffer = lastBuffer, bounds.width > 0, bounds.height > 0 else { return }
        let scale = window?.backingScaleFactor ?? 2
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        guard buffer !== renderedBuffer || size != renderedSize || parameters != renderedParameters else { return }
        let extent = CGRect(origin: .zero, size: size)
        let source = CIImage(cvPixelBuffer: buffer)
        let fill = RecordingCameraCropGeometry.fillRect(sourceSize: source.extent.size, destination: extent, crop: parameters.crop)
        let ratio = fill.width / max(source.extent.width, 0.001)
        let picture = source.transformed(by: CGAffineTransform(
            a: ratio, b: 0, c: 0, d: ratio,
            tx: fill.minX - source.extent.minX * ratio,
            ty: size.height - fill.maxY - source.extent.minY * ratio
        )).cropped(to: extent)
        guard let image = context.createCGImage(picture, from: extent),
              let bitmap = CGContext(data: nil, width: Int(size.width), height: Int(size.height),
                                     bitsPerComponent: 8, bytesPerRow: 0,
                                     space: image.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            AppLog.event("rendering", "camera_bubble_preview_frame_failed", fields: ["outcome": "failure"])
            return
        }
        bitmap.addPath(StudioCameraBubbleFrame.path(in: extent, radius: parameters.radius * scale, squircle: parameters.squircle))
        bitmap.clip()
        bitmap.draw(image, in: extent)
        guard let clipped = bitmap.makeImage(),
              let framed = StudioCameraBubbleFrame.soften(clipped, size: size, radius: parameters.radius * scale,
                                                          squircle: parameters.squircle, canvasWidth: parameters.canvasWidth * scale) else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        layer?.contents = framed
        CATransaction.commit()
        renderedBuffer = buffer
        renderedSize = size
        renderedParameters = parameters
    }
}
