import AppKit
import ApplicationServices
import CoreGraphics

@MainActor
final class CaptureShelfKeyboardShortcuts {
    static let shared = CaptureShelfKeyboardShortcuts()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var activationObserver: NSObjectProtocol?
    private var suppressedKeyCodes: Set<Int64> = []
    private var stopsAfterKeyUp = false

    private init() {}

    static var accessibilityGranted: Bool { AXIsProcessTrusted() }

    static func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        shared.start()
    }

    static func action(for event: NSEvent) -> OverlayCardAction? {
        guard !event.isARepeat,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return nil }
        if event.keyCode == 51 || event.keyCode == 117 { return .close }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c": return .copy
        case "s": return .save
        case "e": return .annotate
        case "p": return .pin
        default: return nil
        }
    }

    func start() {
        stopsAfterKeyUp = false
        guard !CaptureShelf.shared.items.isEmpty else { return }
        if activationObserver == nil {
            activationObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.start() }
            }
        }
        guard eventTap == nil else { return }
        guard Self.accessibilityGranted else {
            NSLog("Quick Access hover shortcuts scope=otherApps outcome=unavailable reason=accessibilityRequired")
            return
        }

        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            let shortcuts = Unmanaged<CaptureShelfKeyboardShortcuts>.fromOpaque(context).takeUnretainedValue()
            return MainActor.assumeIsolated { shortcuts.filter(type: type, event: event) }
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("Quick Access hover shortcuts scope=otherApps outcome=unavailable reason=eventTapUnavailable")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        guard CGEvent.tapIsEnabled(tap: tap) else {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFMachPortInvalidate(tap)
            NSLog("Quick Access hover shortcuts scope=otherApps outcome=unavailable reason=eventTapDisabled")
            return
        }
        eventTap = tap
        runLoopSource = source
        NSLog("Quick Access hover shortcuts scope=otherApps outcome=enabled")
    }

    func stop() {
        if !suppressedKeyCodes.isEmpty {
            stopsAfterKeyUp = true
            return
        }
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        activationObserver = nil
        runLoopSource = nil
        eventTap = nil
        stopsAfterKeyUp = false
    }

    private func filter(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            suppressedKeyCodes.removeAll()
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            NSLog("Quick Access hover shortcuts outcome=eventTapReenabled")
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .keyUp {
            guard suppressedKeyCodes.remove(keyCode) != nil else { return Unmanaged.passUnretained(event) }
            if stopsAfterKeyUp && suppressedKeyCodes.isEmpty {
                Task {
                    if self.stopsAfterKeyUp { self.stop() }
                }
            }
            return nil
        }
        if suppressedKeyCodes.contains(keyCode) { return nil }

        let shelf = CaptureShelf.shared
        guard type == .keyDown, !stopsAfterKeyUp, !shelf.isTucked, !shelf.isMoving,
              !QuickLookPreviewPresenter.isShown, let item = shelf.hoveredItem,
              let keyboardEvent = NSEvent(cgEvent: event), let action = Self.action(for: keyboardEvent),
              shelf.canPerform(action, id: item.id) else { return Unmanaged.passUnretained(event) }

        suppressedKeyCodes.insert(keyCode)
        Task {
            let performed = shelf.perform(action, id: item.id)
            NSLog("Quick Access hover shortcut item=%@ action=%@ outcome=%@ key=consumed", item.id.uuidString, action.rawValue, performed ? "dispatched" : "unavailable")
        }
        return nil
    }
}
