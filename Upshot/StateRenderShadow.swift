import AppKit
import ScreenCaptureKit

struct StateRenderShadowParameters {
    let density: CGFloat
    let radius: CGFloat
    let verticalOffset: CGFloat
    let rimDensity: CGFloat
    let rimRadius: CGFloat

    init(window: NSWindow) {
        let selector = NSSelectorFromString("shadowParameters")
        let parameters = window.responds(to: selector) ? window.value(forKey: "shadowParameters") as? [String: Any] ?? [:] : [:]
        func value(_ key: String, _ fallback: CGFloat) -> CGFloat {
            switch parameters["com.apple.WindowShadow\(key)Active"] {
            case let number as NSNumber: CGFloat(number.doubleValue)
            case let text as String: Double(text).map { CGFloat($0) } ?? fallback
            default: fallback
            }
        }
        density = value("Density", 0.4)
        radius = value("Radius", 20)
        verticalOffset = value("VerticalOffset", 18)
        rimDensity = value("RimDensity", 0.6)
        rimRadius = value("RimRadius", 3)
    }

    var margin: CGFloat { ceil(radius * 3 + verticalOffset) }

    var logValue: String {
        "density=\(density) radius=\(radius) offset=\(verticalOffset) rimDensity=\(rimDensity) rimRadius=\(rimRadius)"
    }
}

final class StateRenderShadowView: NSView {
    init(frame: CGRect, image: CGImage) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contents = image
        layer?.contentsGravity = .resize
        layer?.contentsScale = StateRenderDisplay.scale
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

extension StateRenderStage {
    func addShadows() async throws {
        let targets = windows.dropFirst().filter { $0.hasShadow && $0.isVisible && !($0.contentView is StateRenderShadowView) }
        guard !targets.isEmpty else { return }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let screen = try StateRenderDisplay.screen
        let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw StateRenderFailure(message: "The render display is not available to ScreenCaptureKit for shadows")
        }
        let stack = windows
        var shapes: [(NSWindow, CGImage)] = []
        for target in targets {
            guard let index = stack.firstIndex(where: { $0 === target }) else { continue }
            let listed = try stack[...index].map { window in
                guard let listed = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                    throw StateRenderFailure(message: "ScreenCaptureKit did not list render window \(window.windowNumber) for a shadow")
                }
                return listed
            }
            let displayFrame = try StateRenderDisplay.frame
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = StateRenderDisplay.captureRect(for: displayFrame, on: screen)
            configuration.ignoreShadowsDisplay = true
            configuration.shouldBeOpaque = true
            configuration.showsCursor = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            configuration.width = StateRenderDisplay.pixelWidth
            configuration.height = StateRenderDisplay.pixelHeight
            let scale = StateRenderDisplay.scale
            let crop = CGRect(x: (target.frame.minX - displayFrame.minX) * scale, y: (displayFrame.maxY - target.frame.maxY) * scale,
                              width: target.frame.width * scale, height: target.frame.height * scale).integral
            let with = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: listed), configuration: configuration)
            let without = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, including: Array(listed.dropLast())), configuration: configuration)
            guard let withCrop = with.cropping(to: crop), let withoutCrop = without.cropping(to: crop) else {
                throw StateRenderFailure(message: "Shadow mask crop \(crop) is outside the display frame")
            }
            shapes.append((target, try Self.differenceMask(withCrop, withoutCrop)))
        }
        for (target, shape) in shapes {
            let parameters = StateRenderShadowParameters(window: target)
            let image = try Self.shadowImage(shape: shape, size: target.frame.size, parameters: parameters)
            let frame = target.frame.insetBy(dx: -parameters.margin, dy: -parameters.margin)
            let shadow = StateRenderWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            configure(shadow)
            shadow.isOpaque = false
            shadow.backgroundColor = .clear
            shadow.hasShadow = false
            shadow.contentView = StateRenderShadowView(frame: CGRect(origin: .zero, size: frame.size), image: image)
            shadow.setFrame(frame, display: false)
            insertBelow(shadow, target: target)
            AppLog.event("rendering", "state_renderer_shadow", fields: ["parameters": parameters.logValue, "window": String(describing: target.windowNumber)])
        }
    }

    private static func pixels(of image: CGImage) throws -> [UInt8] {
        var buffer = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { throw StateRenderFailure(message: "sRGB is unavailable") }
        try buffer.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                          bytesPerRow: image.width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw StateRenderFailure(message: "Shadow mask allocation failed")
            }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return buffer
    }

    private static func differenceMask(_ with: CGImage, _ without: CGImage) throws -> CGImage {
        guard with.width == without.width, with.height == without.height else { throw StateRenderFailure(message: "Shadow mask captures differ in size") }
        let first = try pixels(of: with)
        let second = try pixels(of: without)
        var mask = [UInt8](repeating: 0, count: first.count)
        var index = 0
        while index < first.count {
            let difference = max(abs(Int(first[index]) - Int(second[index])), abs(Int(first[index + 1]) - Int(second[index + 1])), abs(Int(first[index + 2]) - Int(second[index + 2])))
            if difference > 3 {
                mask[index] = 255
                mask[index + 1] = 255
                mask[index + 2] = 255
                mask[index + 3] = 255
            }
            index += 4
        }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let provider = CGDataProvider(data: Data(mask) as CFData),
              let image = CGImage(width: with.width, height: with.height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: with.width * 4,
                                  space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw StateRenderFailure(message: "Shadow mask creation failed")
        }
        return image
    }

    private static func shadowImage(shape: CGImage, size: CGSize, parameters: StateRenderShadowParameters) throws -> CGImage {
        let scale = StateRenderDisplay.scale
        let margin = parameters.margin * scale
        let width = Int(size.width * scale + margin * 2)
        let height = Int(size.height * scale + margin * 2)
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw StateRenderFailure(message: "Shadow allocation failed")
        }
        let rect = CGRect(x: margin, y: margin, width: size.width * scale, height: size.height * scale)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -parameters.verticalOffset * scale), blur: parameters.radius * scale * 1.5,
                          color: NSColor.black.withAlphaComponent(parameters.density).cgColor)
        context.draw(shape, in: rect)
        context.restoreGState()
        context.saveGState()
        context.setShadow(offset: .zero, blur: parameters.rimRadius * scale,
                          color: NSColor.black.withAlphaComponent(parameters.rimDensity * 0.5).cgColor)
        context.draw(shape, in: rect)
        context.restoreGState()
        context.setBlendMode(.destinationOut)
        context.draw(shape, in: rect)
        guard let image = context.makeImage() else { throw StateRenderFailure(message: "Shadow rendering failed") }
        return image
    }
}
