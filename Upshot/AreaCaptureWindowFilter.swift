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
        SCContentFilter(display: display, excludingWindows: excludedWindows(in: content))
    }
}
