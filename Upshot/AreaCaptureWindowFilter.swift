import AppKit
import ScreenCaptureKit

enum AreaCaptureWindowFilter {
    static func excludes(windowID: CGWindowID, owner: pid_t?, layer: Int, currentProcess: pid_t,
                         includeAppWindows: Bool, coverWindowIDs: Set<CGWindowID>) -> Bool {
        guard !coverWindowIDs.contains(windowID) else { return false }
        return owner == currentProcess && layer != 0 && !includeAppWindows
    }

    static func excludedWindows(in content: SCShareableContent) -> [SCWindow] {
        let covers = DesktopIconVisibilityService.shared.coverWindowIDs
        return content.windows.filter {
            excludes(windowID: $0.windowID, owner: $0.owningApplication?.processID, layer: $0.windowLayer,
                     currentProcess: getpid(), includeAppWindows: UpshotPreferences.includeAppWindowsInCaptures, coverWindowIDs: covers)
        }
    }

    static func displayFilter(display: SCDisplay, content: SCShareableContent) -> SCContentFilter {
        guard let application = content.applications.first(where: { $0.processID == getpid() }) else {
            return SCContentFilter(display: display, excludingWindows: excludedWindows(in: content))
        }
        let excluded = Set(excludedWindows(in: content).map(\.windowID))
        let covers = DesktopIconVisibilityService.shared.coverWindowIDs
        let included = content.windows.filter {
            covers.contains($0.windowID) || $0.owningApplication?.processID == getpid() && !excluded.contains($0.windowID)
        }
        return SCContentFilter(display: display, excludingApplications: [application], exceptingWindows: included)
    }
}
