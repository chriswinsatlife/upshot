import AppKit
import ScreenCaptureKit

@MainActor
final class ScrollingCaptureFrameSource {
    private struct DisplayRegion {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let filter: SCContentFilter
        let configuration: SCStreamConfiguration
    }

    struct Geometry {
        let displayID: CGDirectDisplayID
        let frame: CGRect
        let scale: CGFloat
    }

    let rect: CGRect
    let scale: CGFloat
    let displayID: CGDirectDisplayID?
    private let displayLayout: [String]
    private let regions: [DisplayRegion]

    init(rect: CGRect, geometry: [Geometry], panelID: CGWindowID) async throws {
        self.rect = rect
        displayLayout = AreaSelectionMemory.displayLayout()
        let participating = geometry.filter { $0.frame.intersects(rect) }
        guard rect.width >= 1, let scale = participating.map(\.scale).max(), rect.height * scale >= 8 else {
            throw ScrollingCaptureError.invalidImage
        }
        self.scale = scale
        guard participating.allSatisfy({ region in
            ActiveDisplayResolver.screen(for: region.displayID)?.frame == region.frame
        }) else { throw ScrollingCaptureError.displayChanged }
        displayID = participating.max {
            let left = $0.frame.intersection(rect)
            let right = $1.frame.intersection(rect)
            return left.width * left.height < right.width * right.height
        }?.displayID
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let excludedWindows = AreaCaptureWindowFilter.excludedWindows(in: content, additionallyExcluding: [panelID])
        regions = try participating.map { region in
            guard let display = content.displays.first(where: { $0.displayID == region.displayID }) else {
                throw ScrollingCaptureError.displayChanged
            }
            let intersection = region.frame.intersection(rect)
            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: intersection.minX - region.frame.minX,
                                               y: region.frame.maxY - intersection.maxY,
                                               width: intersection.width, height: intersection.height)
            configuration.width = Int(ceil(intersection.width * scale))
            configuration.height = Int(ceil(intersection.height * scale))
            configuration.showsCursor = false
            configuration.colorSpaceName = CGColorSpace.sRGB
            let filter = SCContentFilter(display: display, excludingWindows: excludedWindows)
            return DisplayRegion(displayID: region.displayID, frame: intersection, filter: filter, configuration: configuration)
        }
        AppLog.event("capture", "scrolling_capture_source_prepared", fields: ["displays": String(describing: regions.count), "excludedPanel": String(describing: panelID), "scale": String(describing: scale)])
    }

    func captureFrame() async throws -> CGImage {
        guard AreaSelectionMemory.displayLayout() == displayLayout else { throw ScrollingCaptureError.displayChanged }
        var snapshots: [AreaCaptureSnapshot] = []
        for region in regions {
            try Task.checkCancellation()
            let image = try await SCScreenshotManager.captureImage(contentFilter: region.filter, configuration: region.configuration)
            snapshots.append(AreaCaptureSnapshot(displayID: region.displayID, frame: region.frame, image: image))
        }
        try Task.checkCancellation()
        return try AreaCaptureSnapshot.composite(snapshots, in: rect)
    }
}
