
import AppKit
import Observation
import Carbon.HIToolbox

@Observable
final class HotkeyManager {
    
    static let shared = HotkeyManager()
    
    private static let hotKeySignature = OSType(0x4F53_4854)

    private var eventHandlerRef: EventHandlerRef?
    private var hotKeyRefs: [CaptureHotkeyAction: EventHotKeyRef] = [:]
    private(set) var isRecordingShortcut = false
    private(set) var registrationErrors: [CaptureHotkeyAction: String] = [:]
    
    private init() {}

    deinit {
        unregisterHotkeys()

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
    
    func registerHotkeys() {
        installEventHandlerIfNeeded()
        reloadHotkeys()
    }

    func reloadHotkeys() {
        guard !isRecordingShortcut else { return }
        unregisterHotkeys()
        registrationErrors.removeAll()

        var registeredShortcuts: Set<HotkeyShortcut> = []
        for action in CaptureHotkeyAction.allCases {
            guard let shortcut = CaptureHotkeyPreferences.shortcut(for: action) else { continue }
            guard registeredShortcuts.insert(shortcut).inserted else {
                registrationErrors[action] = "This shortcut is assigned to another Upshot action."
                continue
            }

            do {
                hotKeyRefs[action] = try registerHotKey(action: action, shortcut: shortcut)
            } catch {
                registrationErrors[action] = error.localizedDescription
            }
        }
    }

    func replaceShortcuts(_ shortcuts: [CaptureHotkeyAction: HotkeyShortcut]) throws {
        guard !isRecordingShortcut else { throw AutomationError.message("Finish recording the keyboard shortcut before loading configuration.") }
        var bindings: Set<HotkeyShortcut> = []
        for (action, shortcut) in shortcuts {
            guard shortcut.isValid, bindings.insert(shortcut).inserted else {
                throw AutomationError.message("Invalid or conflicting shortcut for \(action.title).")
            }
        }
        let previous = CaptureHotkeyPreferences.shortcuts()
        guard previous != shortcuts else { return }
        installEventHandlerIfNeeded()
        unregisterHotkeys()
        do {
            for action in CaptureHotkeyAction.allCases {
                if let shortcut = shortcuts[action] {
                    hotKeyRefs[action] = try registerHotKey(action: action, shortcut: shortcut)
                }
            }
        } catch {
            unregisterHotkeys()
            reloadHotkeys()
            throw error
        }
        for action in CaptureHotkeyAction.allCases {
            CaptureHotkeyPreferences.saveShortcut(shortcuts[action], for: action)
        }
        registrationErrors.removeAll()
        NSLog("Shortcut catalog loaded bindings=%ld", shortcuts.count)
    }

    func suspendForShortcutRecording() {
        isRecordingShortcut = true
        unregisterHotkeys()
    }

    func resumeAfterShortcutRecording() {
        guard isRecordingShortcut else { return }
        isRecordingShortcut = false
        reloadHotkeys()
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandlerRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &handlerRef
        )

        if status == noErr {
            eventHandlerRef = handlerRef
        } else {
            print("Failed to install hotkey handler, status=\(status)")
        }
    }
    
    func setShortcut(_ shortcut: HotkeyShortcut?, for action: CaptureHotkeyAction) throws {
        if shortcut == CaptureHotkeyPreferences.shortcut(for: action), hotKeyRefs[action] != nil { return }
        installEventHandlerIfNeeded()
        if let shortcut {
            guard shortcut.isValid else { throw AutomationError.message("Use a valid key with at least one modifier.") }
            if let conflict = CaptureHotkeyPreferences.conflictingAction(for: shortcut, excluding: action) {
                throw AutomationError.message("This shortcut is assigned to \(conflict.title).")
            }
        }
        let newRef = try shortcut.map { try registerHotKey(action: action, shortcut: $0) }
        if let oldRef = hotKeyRefs[action] { UnregisterEventHotKey(oldRef) }
        hotKeyRefs[action] = newRef
        CaptureHotkeyPreferences.saveShortcut(shortcut, for: action)
        registrationErrors[action] = nil
        NSLog("Shortcut updated action=%@ binding=%@", action.route, shortcut?.displayString ?? "disabled")
    }

    private func registerHotKey(action: CaptureHotkeyAction, shortcut: HotkeyShortcut) throws -> EventHotKeyRef {
        guard eventHandlerRef != nil else {
            throw NSError(domain: "Upshot.Hotkeys", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Keyboard shortcuts could not be initialized. Try reopening Upshot."
            ])
        }
        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: action.hotKeyID)
        var hotKeyRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), shortcut.modifiers.carbonEventModifiers,
            hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard status == noErr, let hotKeyRef else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [
                NSLocalizedDescriptionKey: "\(shortcut.displayString) could not be registered. It may be used by another app. Choose a different shortcut."
            ])
        }
        return hotKeyRef
    }

    private func unregisterHotkeys() {
        for hotKeyRef in hotKeyRefs.values {
            UnregisterEventHotKey(hotKeyRef)
        }

        hotKeyRefs.removeAll()
    }
    
    func handleHotKey(id: UInt32) {
        guard !isRecordingShortcut else { return }
        CaptureHotkeyAction(hotKeyID: id)?.perform()
    }
}


private func hotKeyHandler(
    nextHandler: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else {
        return OSStatus(eventNotHandledErr)
    }
    
    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        UInt32(kEventParamDirectObject),
        UInt32(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    
    let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.handleHotKey(id: hotKeyID.id)
    
    return noErr
}
