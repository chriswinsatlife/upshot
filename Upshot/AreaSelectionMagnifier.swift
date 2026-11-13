import AppKit
import ScreenCaptureKit

@MainActor
final class AreaSelectionLiveMagnifier {
    private var task: Task<Void, Never>?
    private(set) var image: CGImage?
    private(set) var samplePosition = CGPoint(x: 0.5, y: 0.5)
    private(set) var displayID: CGDirectDisplayID?

    func start(panelIDs: Set<CGWindowID>, snapshots: [AreaCaptureSnapshot], didUpdate: @escaping () -> Void) {
        stop()
        task = Task { @MainActor [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                let excluded = AreaCaptureWindowFilter.excludedWindows(in: content)
                NSLog("Area live magnifier started: excludedWindows=%ld", excluded.count)
                var receivedFrame = false
                while !Task.isCancelled {
                    let pointer = NSEvent.mouseLocation
                    guard let snapshot = snapshots.first(where: { $0.frame.contains(pointer) }),
                          let display = content.displays.first(where: { $0.displayID == snapshot.displayID }) else {
                        try await Task.sleep(for: .milliseconds(120))
                        continue
                    }
                    let pixels = snapshot.magnifierPixelRect(at: pointer)
                    let configuration = SCStreamConfiguration()
                    configuration.sourceRect = CGRect(x: pixels.minX / snapshot.scale, y: pixels.minY / snapshot.scale, width: pixels.width / snapshot.scale, height: pixels.height / snapshot.scale)
                    configuration.width = Int(pixels.width)
                    configuration.height = Int(pixels.height)
                    configuration.showsCursor = false
                    configuration.ignoreShadowsDisplay = false
                    let filter = AreaCaptureWindowFilter.displayFilter(display: display, content: content)
                    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
                    try Task.checkCancellation()
                    self?.samplePosition = snapshot.magnifierSamplePosition(at: pointer)
                    self?.image = image
                    self?.displayID = snapshot.displayID
                    if !receivedFrame {
                        receivedFrame = true
                        NSLog("Area live magnifier updated: display=%u pixels=%ldx%ld", snapshot.displayID, image.width, image.height)
                    }
                    didUpdate()
                    try await Task.sleep(for: .milliseconds(120))
                }
            } catch is CancellationError {
            } catch {
                NSLog("Area live magnifier failed: %@", String(describing: error))
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        image = nil
        displayID = nil
    }
}

struct AreaSelectionReadout {
    let coordinates: String
    let size: String?
    let note: String?
}

enum AreaSelectionMagnifier {
    private static let sampleSide: CGFloat = 17
    private static let loupeSide: CGFloat = 119
    private static let panelPadding: CGFloat = 6
    private static let loupeRadius: CGFloat = 10
    private static let panelRadius: CGFloat = 16
    private static let textInset: CGFloat = 10
    private static let lineSpacing: CGFloat = 3
    private static let pointerOffset: CGFloat = 22
    private static let screenMargin: CGFloat = 8

    private static let sizeFont = font(size: 12, weight: .semibold)
    private static let detailFont = font(size: 11, weight: .medium)
    private static let primaryTextColor = CGColor(gray: 1, alpha: 0.96)
    private static let secondaryTextColor = CGColor(gray: 1, alpha: 0.62)
    private static let panelFill = CGColor(gray: 0.09, alpha: 0.94)
    private static let panelStroke = CGColor(gray: 1, alpha: 0.14)
    private static let loupeStroke = CGColor(gray: 1, alpha: 0.18)
    private static let guideOuter = CGColor(gray: 0, alpha: 0.45)
    private static let guideInner = CGColor(gray: 1, alpha: 0.85)
    private static let pixelOuter = CGColor(gray: 0, alpha: 0.8)
    private static let pixelInner = CGColor(gray: 1, alpha: 1)
    private static let crosshairOuter = CGColor(gray: 0, alpha: 0.45)
    private static let crosshairInner = CGColor(gray: 1, alpha: 0.9)
    private static let selectionOuter = CGColor(gray: 0, alpha: 0.4)
    private static let selectionInner = CGColor(gray: 1, alpha: 1)
    private static let panelShadow = CGColor(gray: 0, alpha: 0.3)
    private static let loupeBackground = CGColor(gray: 0, alpha: 1)

    static func drawSelectionBorder(in context: CGContext, rect: CGRect) {
        context.saveGState()
        context.setLineWidth(1)
        context.setStrokeColor(selectionOuter)
        context.stroke(rect.insetBy(dx: -1.5, dy: -1.5))
        context.setStrokeColor(selectionInner)
        context.stroke(rect.insetBy(dx: -0.5, dy: -0.5))
        context.restoreGState()
    }

    static func draw(in context: CGContext, bounds: CGRect, point: CGPoint, image: CGImage?, samplePosition: CGPoint, readout: AreaSelectionReadout, showsCrosshair: Bool, showsMagnifier: Bool) {
        if showsCrosshair {
            context.saveGState()
            context.setStrokeColor(crosshairOuter)
            context.setLineWidth(1.5)
            crosshair(in: context, bounds: bounds, point: point)
            context.setStrokeColor(crosshairInner)
            context.setLineWidth(0.5)
            crosshair(in: context, bounds: bounds, point: point)
            context.restoreGState()
        }
        let primary = OverlayTextLayout(readout.size ?? readout.coordinates, font: sizeFont, color: primaryTextColor)
        let secondaryText = [readout.size == nil ? nil : readout.coordinates, readout.note].compactMap { $0 }.joined(separator: " · ")
        let secondary = secondaryText.isEmpty ? nil : OverlayTextLayout(secondaryText, font: detailFont, color: secondaryTextColor)
        let textWidth = max(primary.size.width, secondary?.size.width ?? 0)
        let textHeight = primary.size.height + (secondary.map { $0.size.height + lineSpacing } ?? 0)
        let width = showsMagnifier ? max(loupeSide + panelPadding * 2, textWidth + textInset * 2) : textWidth + textInset * 2 + 4
        let height = showsMagnifier ? panelPadding + loupeSide + textInset - 2 + textHeight + textInset - 1 : textHeight + textInset + 4
        let x = point.x + pointerOffset + width <= bounds.maxX - screenMargin ? point.x + pointerOffset : point.x - width - pointerOffset
        let y = point.y - pointerOffset - height >= bounds.minY + screenMargin ? point.y - pointerOffset - height : point.y + pointerOffset
        let frame = CGRect(x: min(max(screenMargin, x), max(screenMargin, bounds.maxX - width - screenMargin)),
                           y: min(max(screenMargin, y), max(screenMargin, bounds.maxY - height - screenMargin)),
                           width: width, height: height).integral
        let radius = showsMagnifier ? panelRadius : frame.height / 2
        let panel = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -4), blur: 14, color: panelShadow)
        context.addPath(panel)
        context.setFillColor(panelFill)
        context.fillPath()
        context.restoreGState()
        context.saveGState()
        context.addPath(panel)
        context.setStrokeColor(panelStroke)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
        if showsMagnifier {
            let loupe = CGRect(x: frame.midX - loupeSide / 2, y: frame.maxY - panelPadding - loupeSide, width: loupeSide, height: loupeSide)
            drawLoupe(in: context, loupe: loupe, image: image, samplePosition: samplePosition)
        }
        let textTop = showsMagnifier ? frame.maxY - panelPadding - loupeSide - textInset + 2 : frame.midY + textHeight / 2
        primary.draw(at: CGPoint(x: frame.midX - primary.size.width / 2, y: textTop - primary.size.height), in: context)
        if let secondary {
            secondary.draw(at: CGPoint(x: frame.midX - secondary.size.width / 2, y: textTop - primary.size.height - lineSpacing - secondary.size.height), in: context)
        }
    }

    private static func drawLoupe(in context: CGContext, loupe: CGRect, image: CGImage?, samplePosition: CGPoint) {
        let shape = CGPath(roundedRect: loupe, cornerWidth: loupeRadius, cornerHeight: loupeRadius, transform: nil)
        context.saveGState()
        context.addPath(shape)
        context.clip()
        context.setFillColor(loupeBackground)
        context.fill(loupe)
        if let image {
            context.interpolationQuality = .none
            context.draw(image, in: loupe)
        }
        let cell = loupe.width / sampleSide
        let center = CGPoint(x: loupe.minX + samplePosition.x * loupe.width, y: loupe.minY + samplePosition.y * loupe.height)
        let pixel = CGRect(x: center.x - cell / 2, y: center.y - cell / 2, width: cell, height: cell)
        context.setLineWidth(1)
        context.setStrokeColor(guideOuter)
        guides(in: context, loupe: loupe, pixel: pixel.insetBy(dx: -1, dy: -1), offset: 0.5)
        context.setStrokeColor(guideInner)
        guides(in: context, loupe: loupe, pixel: pixel, offset: 0)
        context.setStrokeColor(pixelOuter)
        context.stroke(pixel.insetBy(dx: -1, dy: -1))
        context.setStrokeColor(pixelInner)
        context.stroke(pixel)
        context.restoreGState()
        context.saveGState()
        context.addPath(shape)
        context.setStrokeColor(loupeStroke)
        context.setLineWidth(1)
        context.strokePath()
        context.restoreGState()
    }

    private static func guides(in context: CGContext, loupe: CGRect, pixel: CGRect, offset: CGFloat) {
        let midX = pixel.midX + offset
        let midY = pixel.midY + offset
        context.move(to: CGPoint(x: loupe.minX, y: midY))
        context.addLine(to: CGPoint(x: pixel.minX, y: midY))
        context.move(to: CGPoint(x: pixel.maxX, y: midY))
        context.addLine(to: CGPoint(x: loupe.maxX, y: midY))
        context.move(to: CGPoint(x: midX, y: loupe.minY))
        context.addLine(to: CGPoint(x: midX, y: pixel.minY))
        context.move(to: CGPoint(x: midX, y: pixel.maxY))
        context.addLine(to: CGPoint(x: midX, y: loupe.maxY))
        context.strokePath()
    }

    private static func crosshair(in context: CGContext, bounds: CGRect, point: CGPoint) {
        context.move(to: CGPoint(x: bounds.minX, y: point.y))
        context.addLine(to: CGPoint(x: bounds.maxX, y: point.y))
        context.move(to: CGPoint(x: point.x, y: bounds.minY))
        context.addLine(to: CGPoint(x: point.x, y: bounds.maxY))
        context.strokePath()
    }

    private static func font(size: CGFloat, weight: NSFont.Weight) -> CTFont {
        let font = NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
        return CTFontCreateCopyWithAttributes(font as CTFont, size, nil, nil)
    }
}
