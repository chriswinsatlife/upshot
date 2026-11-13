import AppKit
import ScreenCaptureKit

enum AreaCaptureWindowFilter {
    static var alwaysExcludedWindowIDs: Set<CGWindowID> = []

    static func excludes(windowID: CGWindowID, owner: pid_t?, layer: Int, currentProcess: pid_t,
                         includeAppWindows: Bool, coverWindowIDs: Set<CGWindowID>,
                         alwaysExcludedWindowIDs: Set<CGWindowID> = []) -> Bool {
        if alwaysExcludedWindowIDs.contains(windowID) { return true }
        guard !coverWindowIDs.contains(windowID) else { return false }
        return owner == currentProcess && layer != 0 && !includeAppWindows
    }

    static func excludedWindows(in content: SCShareableContent, additionallyExcluding extraWindowIDs: Set<CGWindowID> = []) -> [SCWindow] {
        let covers = DesktopIconVisibilityService.shared.coverWindowIDs
        let always = alwaysExcludedWindowIDs.union(extraWindowIDs)
        return content.windows.filter {
            excludes(windowID: $0.windowID, owner: $0.owningApplication?.processID, layer: $0.windowLayer,
                     currentProcess: getpid(), includeAppWindows: UpshotPreferences.includeAppWindowsInCaptures,
                     coverWindowIDs: covers, alwaysExcludedWindowIDs: always)
        }
    }

    static func displayFilter(display: SCDisplay, content: SCShareableContent, additionallyExcluding extraWindowIDs: Set<CGWindowID> = []) -> SCContentFilter {
        SCContentFilter(display: display, excludingWindows: excludedWindows(in: content, additionallyExcluding: extraWindowIDs))
    }
}
