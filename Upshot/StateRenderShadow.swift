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
        for target in targets {
            guard let listed = content.windows.first(where: { $0.windowID == CGWindowID(target.windowNumber) }) else {
                throw StateRenderFailure(message: "ScreenCaptureKit did not list render window \(target.windowNumber) for its shadow")
            }
            let filter = SCContentFilter(desktopIndependentWindow: listed)
            let configuration = SCStreamConfiguration()
            configuration.ignoreShadowsSingleWindow = true
            configuration.shouldBeOpaque = false
            configuration.showsCursor = false
            configuration.width = Int(target.frame.width * StateRenderDisplay.scale)
            configuration.height = Int(target.frame.height * StateRenderDisplay.scale)
            let shape: CGImage
            do {
                shape = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
            } catch {
                throw StateRenderFailure(message: "Shadow shape capture failed for \(type(of: target)) frame=\(target.frame) listed=\(listed.frame) filter=\(filter.contentRect) size=\(configuration.width)x\(configuration.height): \(error.localizedDescription)")
            }
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
