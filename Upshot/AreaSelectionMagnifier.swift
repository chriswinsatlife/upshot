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
                let excluded = content.windows.filter { panelIDs.contains($0.windowID) }
                guard excluded.count == panelIDs.count else {
                    NSLog("Area live magnifier unavailable: selector windows could not be excluded")
                    return
                }
                NSLog("Area live magnifier started: excludedWindows=%ld", excluded.count)
                while !Task.isCancelled {
                    let pointer = NSEvent.mouseLocation
                    guard let snapshot = snapshots.first(where: { $0.frame.contains(pointer) }),
                          let display = content.displays.first(where: { $0.displayID == snapshot.displayID }) else {
                        try await Task.sleep(for: .milliseconds(120))
                        continue
                    }
                    let side = 17 / snapshot.scale
                    let sample = CGRect(x: min(max(pointer.x - side / 2, snapshot.frame.minX), snapshot.frame.maxX - side),
                                        y: min(max(pointer.y - side / 2, snapshot.frame.minY), snapshot.frame.maxY - side), width: side, height: side)
                    let configuration = SCStreamConfiguration()
                    configuration.sourceRect = CGRect(x: sample.minX - snapshot.frame.minX, y: snapshot.frame.maxY - sample.maxY, width: side, height: side)
                    configuration.width = 17
                    configuration.height = 17
                    configuration.showsCursor = false
                    configuration.ignoreShadowsDisplay = false
                    let image = try await SCScreenshotManager.captureImage(contentFilter: SCContentFilter(display: display, excludingWindows: excluded), configuration: configuration)
                    try Task.checkCancellation()
                    self?.samplePosition = CGPoint(x: (pointer.x - sample.minX) / side, y: (pointer.y - sample.minY) / side)
                    self?.image = image
                    self?.displayID = snapshot.displayID
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

enum AreaSelectionMagnifier {
    static func draw(in context: CGContext, bounds: CGRect, point: CGPoint, image: CGImage?, samplePosition: CGPoint, readout: String, showsCrosshair: Bool, showsMagnifier: Bool) {
        if showsCrosshair {
            context.saveGState()
            context.setStrokeColor(NSColor.black.withAlphaComponent(0.7).cgColor)
            context.setLineWidth(2)
            crosshair(in: context, bounds: bounds, point: point)
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
            context.setLineWidth(0.5)
            crosshair(in: context, bounds: bounds, point: point)
            context.restoreGState()
        }
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white]
        let readoutSize = (readout as NSString).size(withAttributes: attributes)
        let width = max(132, readoutSize.width + 20)
        let height: CGFloat = showsMagnifier ? 148 : 32
        let x = min(max(8, point.x + 22 + width <= bounds.maxX - 8 ? point.x + 22 : point.x - width - 22), max(8, bounds.maxX - width - 8))
        let y = min(max(8, point.y + 22 + height <= bounds.maxY - 8 ? point.y + 22 : point.y - height - 22), max(8, bounds.maxY - height - 8))
        let frame = CGRect(x: x, y: y, width: width, height: height)
        NSColor.black.withAlphaComponent(0.92).setFill()
        NSBezierPath(roundedRect: frame, xRadius: 10, yRadius: 10).fill()
        if showsMagnifier {
            let loupe = CGRect(x: frame.midX - 54, y: frame.minY + 32, width: 108, height: 108)
            context.saveGState()
            context.clip(to: loupe)
            if let image {
                context.interpolationQuality = .none
                context.draw(image, in: loupe)
            }
            context.setStrokeColor(NSColor.black.cgColor)
            context.setLineWidth(2)
            crosshair(in: context, bounds: loupe, point: CGPoint(x: loupe.minX + samplePosition.x * loupe.width, y: loupe.minY + samplePosition.y * loupe.height))
            context.setStrokeColor(NSColor.white.cgColor)
            context.setLineWidth(0.5)
            crosshair(in: context, bounds: loupe, point: CGPoint(x: loupe.minX + samplePosition.x * loupe.width, y: loupe.minY + samplePosition.y * loupe.height))
            context.restoreGState()
        }
        (readout as NSString).draw(at: CGPoint(x: frame.midX - readoutSize.width / 2, y: frame.minY + 10), withAttributes: attributes)
    }

    private static func crosshair(in context: CGContext, bounds: CGRect, point: CGPoint) {
        context.move(to: CGPoint(x: bounds.minX, y: point.y))
        context.addLine(to: CGPoint(x: bounds.maxX, y: point.y))
        context.move(to: CGPoint(x: point.x, y: bounds.minY))
        context.addLine(to: CGPoint(x: point.x, y: bounds.maxY))
        context.strokePath()
    }
}
