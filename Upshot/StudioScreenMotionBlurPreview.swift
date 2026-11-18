import AppKit
import AVFoundation
import CoreVideo
import Metal
import MetalPerformanceShaders
import QuartzCore
import SwiftUI

struct StudioScreenMotionBlurPreview: NSViewRepresentable {
    let player: AVPlayer
    let drawRect: CGRect
    let cardRect: CGRect
    let canvasSize: CGSize
    let time: TimeInterval
    let isPlaying: Bool
    let shutterFraction: Double

    func makeNSView(context: Context) -> StudioScreenMotionBlurLayerView {
        StudioScreenMotionBlurLayerView()
    }

    func updateNSView(_ view: StudioScreenMotionBlurLayerView, context: Context) {
        view.update(
            player: player, drawRect: drawRect, cardRect: cardRect, canvasSize: canvasSize,
            time: time, isPlaying: isPlaying, shutterFraction: shutterFraction
        )
    }

    static func dismantleNSView(_ view: StudioScreenMotionBlurLayerView, coordinator: ()) {
        view.stop()
    }
}

final class StudioScreenMotionBlurLayerView: NSView {
    private let metalLayer = CAMetalLayer()
    private let device: MTLDevice?
    private let queue: MTLCommandQueue?
    private let pipeline: MTLComputePipelineState?
    private let downsampler: MPSImageLanczosScale?
    private var downsampledTexture: MTLTexture?
    private var downsampledSource: CVPixelBuffer?
    private var textureCache: CVMetalTextureCache?
    private weak var item: AVPlayerItem?
    private var output: AVPlayerItemVideoOutput?
    private var timeJumpObserver: NSObjectProtocol?
    private var screenFrame: CVPixelBuffer?
    private var playback = StudioScreenMotionBlurPlayback()
    private var didReportFailure = false

    override init(frame frameRect: NSRect) {
        let device = MTLCreateSystemDefaultDevice()
        self.device = device
        queue = device?.makeCommandQueue()
        let downsampler = device.map { MPSImageLanczosScale(device: $0) }
        downsampler?.edgeMode = .clamp
        self.downsampler = downsampler
        if let device, let function = device.makeDefaultLibrary()?.makeFunction(name: "studioPreviewMotionBlur") {
            pipeline = try? device.makeComputePipelineState(function: function)
        } else {
            pipeline = nil
        }
        var cache: CVMetalTextureCache?
        if let device { CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache) }
        textureCache = cache
        super.init(frame: frameRect)
        metalLayer.device = device
        metalLayer.pixelFormat = .bgra8Unorm
        metalLayer.framebufferOnly = false
        metalLayer.isOpaque = false
        metalLayer.isHidden = true
        wantsLayer = true
        layerContentsRedrawPolicy = .never
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func makeBackingLayer() -> CALayer { metalLayer }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func stop() {
        if let timeJumpObserver { NotificationCenter.default.removeObserver(timeJumpObserver) }
        timeJumpObserver = nil
        if let item, let output { item.remove(output) }
        item = nil
        output = nil
        screenFrame = nil
        downsampledSource = nil
        playback = StudioScreenMotionBlurPlayback()
        metalLayer.isHidden = true
    }

    func update(
        player: AVPlayer, drawRect: CGRect, cardRect: CGRect, canvasSize: CGSize,
        time: TimeInterval, isPlaying: Bool, shutterFraction: Double
    ) {
        if item !== player.currentItem {
            stop()
            if let current = player.currentItem {
                let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferMetalCompatibilityKey as String: true,
                    kCVPixelBufferIOSurfacePropertiesKey as String: [String: Int]()
                ])
                current.add(output)
                self.item = current
                self.output = output
                timeJumpObserver = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.timeJumpedNotification, object: current, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.playback = StudioScreenMotionBlurPlayback()
                        self?.screenFrame = nil
                        self?.metalLayer.isHidden = true
                    }
                }
            }
        }
        let motion = playback.sample(
            at: time, rect: drawRect, stageSize: canvasSize,
            isPlaying: isPlaying, shutterFraction: shutterFraction
        )
        guard motion.isActive, !didReportFailure else {
            metalLayer.isHidden = true
            return
        }
        let itemTime = player.currentTime()
        if let output, output.hasNewPixelBuffer(forItemTime: itemTime),
           let frame = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
            screenFrame = frame
        }
        guard let screenFrame, cardRect.width > 0, cardRect.height > 0 else {
            metalLayer.isHidden = true
            return
        }
        guard let device, let queue, let pipeline, let textureCache, let downsampler else {
            reportFailure("initialization")
            return
        }
        let scale = window?.backingScaleFactor ?? 2
        let size = CGSize(width: max(1, (cardRect.width * scale).rounded()), height: max(1, (cardRect.height * scale).rounded()))
        metalLayer.contentsScale = scale
        if metalLayer.drawableSize != size { metalLayer.drawableSize = size }
        if let attachments = CVBufferCopyAttachments(screenFrame, .shouldPropagate),
           let colorSpace = CVImageBufferCreateColorSpaceFromAttachments(attachments)?.takeRetainedValue() {
            metalLayer.colorspace = colorSpace
        } else {
            metalLayer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        }
        var source: CVMetalTexture?
        guard CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, textureCache, screenFrame, nil, .bgra8Unorm,
            CVPixelBufferGetWidth(screenFrame), CVPixelBufferGetHeight(screenFrame), 0, &source
        ) == kCVReturnSuccess, let source, let texture = CVMetalTextureGetTexture(source) else {
            reportFailure("source_texture")
            return
        }
        let localRect = CGRect(
            x: (drawRect.minX - cardRect.minX) * scale, y: (drawRect.minY - cardRect.minY) * scale,
            width: drawRect.width * scale, height: drawRect.height * scale
        )
        guard let drawable = metalLayer.nextDrawable(), let command = queue.makeCommandBuffer() else {
            metalLayer.isHidden = true
            return
        }
        var sampledTexture = texture
        let sampledWidth = max(1, Int(min(CGFloat(texture.width), ceil(localRect.width * 2))))
        let sampledHeight = max(1, Int(min(CGFloat(texture.height), ceil(localRect.height * 2))))
        if sampledWidth < texture.width || sampledHeight < texture.height {
            if downsampledTexture?.width != sampledWidth || downsampledTexture?.height != sampledHeight {
                let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                    pixelFormat: .bgra8Unorm, width: sampledWidth, height: sampledHeight, mipmapped: false
                )
                descriptor.usage = [.shaderRead, .shaderWrite]
                descriptor.storageMode = .private
                downsampledTexture = device.makeTexture(descriptor: descriptor)
                downsampledSource = nil
            }
            guard let downsampledTexture else {
                reportFailure("downsample_texture")
                return
            }
            if downsampledSource !== screenFrame {
                downsampler.encode(commandBuffer: command, sourceTexture: texture, destinationTexture: downsampledTexture)
            }
            sampledTexture = downsampledTexture
        }
        guard let encoder = command.makeComputeCommandEncoder() else {
            reportFailure("compute_encoder")
            return
        }
        var rect = SIMD4<Float>(Float(localRect.minX), Float(localRect.minY), Float(localRect.width), Float(localRect.height))
        let scaledMotion = motion.scaled(by: scale, origin: cardRect.origin)
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(sampledTexture, index: 0)
        encoder.setTexture(drawable.texture, index: 1)
        encoder.setBytes(&rect, length: MemoryLayout<SIMD4<Float>>.size, index: 0)
        scaledMotion.parameters.withUnsafeBytes { bytes in
            encoder.setBytes(bytes.baseAddress!, length: bytes.count, index: 3)
        }
        let width = pipeline.threadExecutionWidth
        encoder.dispatchThreads(
            MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1),
            threadsPerThreadgroup: MTLSize(width: width, height: min(8, pipeline.maxTotalThreadsPerThreadgroup / width), depth: 1)
        )
        encoder.endEncoding()
        let retained = StudioScreenMotionBlurFrame(texture: source, buffer: screenFrame)
        command.addCompletedHandler { [weak self, retained] completed in
            withExtendedLifetime(retained) {}
            if completed.status == .error {
                Task { @MainActor [weak self] in self?.reportFailure("command") }
            }
        }
        command.present(drawable)
        command.commit()
        downsampledSource = sampledTexture === downsampledTexture ? screenFrame : nil
        metalLayer.isHidden = false
    }

    private func reportFailure(_ reason: String) {
        metalLayer.isHidden = true
        guard !didReportFailure else { return }
        didReportFailure = true
        AppLog.event("rendering", "screen_motion_blur_preview_failed", fields: ["reason": reason])
    }
}

nonisolated private final class StudioScreenMotionBlurFrame: @unchecked Sendable {
    let texture: CVMetalTexture
    let buffer: CVPixelBuffer

    init(texture: CVMetalTexture, buffer: CVPixelBuffer) {
        self.texture = texture
        self.buffer = buffer
    }
}
