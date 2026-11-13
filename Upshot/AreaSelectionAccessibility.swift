import AppKit
import ApplicationServices

enum AreaSelectionAccessibility {
    static var hasPermission: Bool { AXIsProcessTrusted() }

    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        NSLog("Smart element permission requested: trusted=%d", trusted)
    }

    static func frame(at point: CGPoint, processID: pid_t) -> CGRect? {
        guard hasPermission else { return nil }
        let application = AXUIElementCreateApplication(processID)
        AXUIElementSetMessagingTimeout(application, 0.15)
        let quartz = ActiveDisplayResolver.quartzPoint(fromAppKit: point)
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(application, Float(quartz.x), Float(quartz.y), &element) == .success,
              let element else { return nil }
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        let position = positionValue as! AXValue
        let size = sizeValue as! AXValue
        guard AXValueGetType(position) == .cgPoint, AXValueGetType(size) == .cgSize else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &dimensions),
              origin.x.isFinite, origin.y.isFinite, dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width >= 1, dimensions.height >= 1 else { return nil }
        return ActiveDisplayResolver.appKitRect(fromQuartz: CGRect(origin: origin, size: dimensions))
    }
}
