import AppKit
import ObjectiveC

@MainActor
enum LiveStateInteractionGuards {
    private static var installed: [String] = []
    private static var menuObservers: [NSObjectProtocol] = []
    static var stageWindows: () -> Set<ObjectIdentifier> = { [] }

    nonisolated static let blockedOpenError = NSError(domain: "UyuniLiveState", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "A live state process does not open URLs, files, or applications.",
    ])

    static func install() -> [String] {
        var missing: [String] = []
        func replace(_ owner: AnyClass, _ selectorName: String, classMethod: Bool = false, _ block: Any) {
            let name = "\(classMethod ? "+" : "-")[\(NSStringFromClass(owner)) \(selectorName)]"
            guard !installed.contains(name) else { return }
            let selector = NSSelectorFromString(selectorName)
            guard let target: AnyClass = classMethod ? object_getClass(owner) : owner,
                  let method = class_getInstanceMethod(target, selector) else {
                missing.append(name)
                return
            }
            let implementation = imp_implementationWithBlock(block)
            if !class_addMethod(target, selector, implementation, method_getTypeEncoding(method)) {
                method_setImplementation(method, implementation)
            }
            installed.append(name)
        }

        typealias OpenCompletion = @convention(block) (NSRunningApplication?, NSError?) -> Void
        let openURL: @convention(block) (NSWorkspace, NSURL) -> Bool = { _, url in
            blocked("workspace_open_url", ["url": url.absoluteString ?? ""])
            return false
        }
        let openURLWithConfiguration: @convention(block) (NSWorkspace, NSURL, NSWorkspace.OpenConfiguration, OpenCompletion?) -> Void = { _, url, _, completion in
            blocked("workspace_open_url", ["url": url.absoluteString ?? ""])
            completion?(nil, blockedOpenError)
        }
        let openURLsWithApplication: @convention(block) (NSWorkspace, NSArray, NSURL, NSWorkspace.OpenConfiguration, OpenCompletion?) -> Void = { _, urls, application, _, completion in
            blocked("workspace_open_urls_with_application", ["urls": urls.count, "application": application.lastPathComponent ?? ""])
            completion?(nil, blockedOpenError)
        }
        let openApplication: @convention(block) (NSWorkspace, NSURL, NSWorkspace.OpenConfiguration, OpenCompletion?) -> Void = { _, application, _, completion in
            blocked("workspace_open_application", ["application": application.lastPathComponent ?? ""])
            completion?(nil, blockedOpenError)
        }
        let openFile: @convention(block) (NSWorkspace, NSString) -> Bool = { _, path in
            blocked("workspace_open_file", ["file": path.lastPathComponent])
            return false
        }
        let activateFileViewer: @convention(block) (NSWorkspace, NSArray) -> Void = { _, urls in
            blocked("workspace_activate_file_viewer", ["urls": urls.count])
        }
        let selectFile: @convention(block) (NSWorkspace, NSString?, NSString) -> Bool = { _, path, _ in
            blocked("workspace_select_file", ["file": path?.lastPathComponent ?? ""])
            return false
        }
        replace(NSWorkspace.self, "openURL:", openURL)
        replace(NSWorkspace.self, "openURL:configuration:completionHandler:", openURLWithConfiguration)
        replace(NSWorkspace.self, "openURLs:withApplicationAtURL:configuration:completionHandler:", openURLsWithApplication)
        replace(NSWorkspace.self, "openApplicationAtURL:configuration:completionHandler:", openApplication)
        replace(NSWorkspace.self, "openFile:", openFile)
        replace(NSWorkspace.self, "activateFileViewerSelectingURLs:", activateFileViewer)
        replace(NSWorkspace.self, "selectFile:inFileViewerRootedAtPath:", selectFile)

        let activate: @convention(block) (NSRunningApplication, UInt) -> Bool = { application, _ in
            blocked("application_activation", ["application": application.localizedName ?? "", "processIdentifier": Int(application.processIdentifier)])
            return false
        }
        let activateFrom: @convention(block) (NSRunningApplication, NSRunningApplication, UInt) -> Bool = { application, _, _ in
            blocked("application_activation", ["application": application.localizedName ?? "", "processIdentifier": Int(application.processIdentifier)])
            return false
        }
        replace(NSRunningApplication.self, "activateWithOptions:", activate)
        replace(NSRunningApplication.self, "activateFromApplication:options:", activateFrom)
        let activateIgnoringOtherApps: @convention(block) (NSApplication, Bool) -> Void = { _, ignoringOtherApps in
            blocked("application_activation", ["method": "activateIgnoringOtherApps:", "ignoringOtherApps": ignoringOtherApps])
        }
        let activateApplication: @convention(block) (NSApplication) -> Void = { _ in
            blocked("application_activation", ["method": "activate"])
        }
        let makeKeyWindow: @convention(block) (NSWindow) -> Void = { window in
            blocked("window_made_key", ["class": String(describing: type(of: window)), "windowNumber": window.windowNumber])
        }
        replace(NSApplication.self, "activateIgnoringOtherApps:", activateIgnoringOtherApps)
        replace(NSApplication.self, "activate", activateApplication)
        replace(NSWindow.self, "makeKeyWindow", makeKeyWindow)
        let setActivationPolicy: @convention(block) (NSApplication, Int) -> Bool = { _, policy in
            guard policy != NSApplication.ActivationPolicy.prohibited.rawValue else { return true }
            blocked("activation_policy_change", ["requestedPolicy": policy, "callers": Array(Thread.callStackSymbols.dropFirst().prefix(8))])
            return false
        }
        replace(NSApplication.self, "setActivationPolicy:", setActivationPolicy)

        let popUpMenu: @convention(block) (NSMenu, NSMenuItem?, NSPoint, NSView?) -> Bool = { menu, item, location, view in
            let (window, point) = windowPoint(location, in: view)
            _ = presentMenu(menu, window: window, anchor: .item(item, topLeft: point), source: "menu_pop_up")
            return false
        }
        let popUpMenuWithAppearance: @convention(block) (NSMenu, NSMenuItem?, NSPoint, NSView?, NSAppearance?) -> Bool = { menu, item, location, view, _ in
            let (window, point) = windowPoint(location, in: view)
            _ = presentMenu(menu, window: window, anchor: .item(item, topLeft: point), source: "menu_pop_up")
            return false
        }
        let popUpContextMenu: @convention(block) (AnyObject, NSMenu, NSEvent, NSView) -> Void = { _, menu, event, view in
            let window = view.window ?? event.window
            let point = event.window === window ? event.locationInWindow : window.map { $0.convertPoint(fromScreen: NSEvent.mouseLocation) } ?? .zero
            _ = presentMenu(menu, window: window, anchor: .item(nil, topLeft: point), source: "context_menu_pop_up")
        }
        let popUpContextMenuWithFont: @convention(block) (AnyObject, NSMenu, NSEvent, NSView, NSFont?) -> Void = { _, menu, event, view, _ in
            let window = view.window ?? event.window
            let point = event.window === window ? event.locationInWindow : window.map { $0.convertPoint(fromScreen: NSEvent.mouseLocation) } ?? .zero
            _ = presentMenu(menu, window: window, anchor: .item(nil, topLeft: point), source: "context_menu_pop_up")
        }
        let trackPopUpButton: @convention(block) (NSPopUpButtonCell, NSEvent, NSRect, NSView, Bool) -> Bool = { cell, _, cellFrame, view, _ in
            if let menu = cell.menu {
                _ = presentMenu(menu, window: view.window, anchor: .popUpButton(cell, view.convert(cellFrame, to: nil)), source: "pop_up_button_menu")
            }
            return true
        }
        let performPopUpButtonClick: @convention(block) (NSPopUpButtonCell, NSRect, NSView?) -> Void = { cell, cellFrame, view in
            guard let menu = cell.menu, let view = view ?? cell.controlView else { return }
            _ = presentMenu(menu, window: view.window, anchor: .popUpButton(cell, view.convert(cellFrame, to: nil)), source: "pop_up_button_menu")
        }
        replace(NSMenu.self, "popUpMenuPositioningItem:atLocation:inView:", popUpMenu)
        replace(NSMenu.self, "popUpMenuPositioningItem:atLocation:inView:appearance:", popUpMenuWithAppearance)
        replace(NSMenu.self, "popUpContextMenu:withEvent:forView:", classMethod: true, popUpContextMenu)
        replace(NSMenu.self, "popUpContextMenu:withEvent:forView:withFont:", classMethod: true, popUpContextMenuWithFont)
        replace(NSPopUpButtonCell.self, "trackMouse:inRect:ofView:untilMouseUp:", trackPopUpButton)
        replace(NSPopUpButtonCell.self, "performClickWithFrame:inView:", performPopUpButtonClick)

        let beginDraggingWithEvent: @convention(block) (NSView, NSArray, NSEvent, AnyObject) -> NSDraggingSession? = { view, items, _, _ in
            blocked("dragging_session", ["view": String(describing: type(of: view)), "items": items.count, "start": "event"])
            return nil
        }
        let beginDraggingWithGesture: @convention(block) (NSView, NSArray, NSGestureRecognizer, AnyObject) -> NSDraggingSession? = { view, items, gesture, _ in
            blocked("dragging_session", ["view": String(describing: type(of: view)), "items": items.count, "start": "gesture",
                                         "gesture": String(describing: type(of: gesture))])
            return nil
        }
        let dragImage: @convention(block) (NSView, NSImage, NSPoint, NSSize, NSEvent, NSPasteboard, AnyObject, Bool) -> Void = { view, _, _, _, _, _, _, _ in
            blocked("dragging_session", ["view": String(describing: type(of: view)), "items": 1, "start": "image"])
        }
        let dragFile: @convention(block) (NSView, NSString, NSRect, Bool, NSEvent) -> Bool = { view, _, _, _, _ in
            blocked("dragging_session", ["view": String(describing: type(of: view)), "items": 1, "start": "file"])
            return false
        }
        replace(NSView.self, "beginDraggingSessionWithItems:event:source:", beginDraggingWithEvent)
        replace(NSView.self, "beginDraggingSessionWithItems:gesture:source:", beginDraggingWithGesture)
        replace(NSView.self, "dragImage:at:offset:event:pasteboard:source:slideBack:", dragImage)
        replace(NSView.self, "dragFile:fromRect:slideBack:event:", dragFile)

        typealias ModalCompletion = @convention(block) (Int) -> Void
        let cancel = NSApplication.ModalResponse.cancel.rawValue
        let abort = NSApplication.ModalResponse.abort.rawValue
        let runPanel: @convention(block) (NSSavePanel) -> Int = { panel in
            blocked("file_panel", ["class": String(describing: type(of: panel)), "response": cancel])
            return cancel
        }
        let beginPanel: @convention(block) (NSSavePanel, ModalCompletion?) -> Void = { panel, completion in
            blocked("file_panel", ["class": String(describing: type(of: panel)), "response": cancel])
            DispatchQueue.main.async { completion?(cancel) }
        }
        let beginPanelSheet: @convention(block) (NSSavePanel, NSWindow, ModalCompletion?) -> Void = { panel, _, completion in
            blocked("file_panel", ["class": String(describing: type(of: panel)), "response": cancel])
            DispatchQueue.main.async { completion?(cancel) }
        }
        replace(NSSavePanel.self, "runModal", runPanel)
        replace(NSSavePanel.self, "beginWithCompletionHandler:", beginPanel)
        replace(NSSavePanel.self, "beginSheetModalForWindow:completionHandler:", beginPanelSheet)

        let sheets = LiveStateSheetPresenter.shared
        let runAlert: @convention(block) (NSAlert) -> Int = { alert in
            if let response = sheets.runModalAlert(alert) { return response.rawValue }
            let response = cancellationResponse(of: alert)
            blocked("alert_modal_session", alertFields(alert, response: response))
            return response
        }
        let beginAlertSheet: @convention(block) (NSAlert, NSWindow, ModalCompletion?) -> Void = { alert, window, completion in
            if sheets.presentAlertSheet(alert, for: window, completion: modalCompletion(completion)) { return }
            let response = cancellationResponse(of: alert)
            blocked("alert_sheet", alertFields(alert, response: response))
            DispatchQueue.main.async { completion?(response) }
        }
        let runModalWindow: @convention(block) (NSApplication, NSWindow) -> Int = { _, window in
            if let response = sheets.runModalWindow(window) { return response.rawValue }
            blocked("window_modal_session", ["class": String(describing: type(of: window)), "response": abort])
            return abort
        }
        let beginSheet: @convention(block) (NSWindow, NSWindow, ModalCompletion?) -> Void = { parent, sheet, completion in
            if sheets.presentWindowSheet(sheet, for: parent, completion: modalCompletion(completion)) { return }
            blocked("window_sheet", ["class": String(describing: type(of: sheet)), "response": abort])
            DispatchQueue.main.async { completion?(abort) }
        }
        replace(NSAlert.self, "runModal", runAlert)
        replace(NSAlert.self, "beginSheetModalForWindow:completionHandler:", beginAlertSheet)
        replace(NSApplication.self, "runModalForWindow:", runModalWindow)
        replace(NSWindow.self, "beginSheet:completionHandler:", beginSheet)
        replace(NSWindow.self, "beginCriticalSheet:completionHandler:", beginSheet)

        func passThrough(_ owner: AnyClass, _ selectorName: String, _ makeBlock: (IMP) -> Any) {
            let name = "-[\(NSStringFromClass(owner)) \(selectorName)]"
            guard !installed.contains(name) else { return }
            guard let method = class_getInstanceMethod(owner, NSSelectorFromString(selectorName)) else {
                missing.append(name)
                return
            }
            let original = method_getImplementation(method)
            let implementation = imp_implementationWithBlock(makeBlock(original))
            if !class_addMethod(owner, NSSelectorFromString(selectorName), implementation, method_getTypeEncoding(method)) {
                method_setImplementation(method, implementation)
            }
            installed.append(name)
        }
        typealias EndSheetFunction = @convention(c) (AnyObject, Selector, NSWindow) -> Void
        typealias EndSheetWithCodeFunction = @convention(c) (AnyObject, Selector, NSWindow, Int) -> Void
        typealias StopModalFunction = @convention(c) (AnyObject, Selector) -> Void
        typealias StopModalWithCodeFunction = @convention(c) (AnyObject, Selector, Int) -> Void
        let stop = NSApplication.ModalResponse.stop.rawValue
        for owner in [NSWindow.self, NSApplication.self] as [AnyClass] {
            passThrough(owner, "endSheet:") { original in
                let call = unsafeBitCast(original, to: EndSheetFunction.self)
                let block: @convention(block) (AnyObject, NSWindow) -> Void = { this, sheet in
                    if sheets.endSheet(sheet, response: NSApplication.ModalResponse(rawValue: stop)) { return }
                    call(this, NSSelectorFromString("endSheet:"), sheet)
                }
                return block
            }
            passThrough(owner, "endSheet:returnCode:") { original in
                let call = unsafeBitCast(original, to: EndSheetWithCodeFunction.self)
                let block: @convention(block) (AnyObject, NSWindow, Int) -> Void = { this, sheet, code in
                    if sheets.endSheet(sheet, response: NSApplication.ModalResponse(rawValue: code)) { return }
                    call(this, NSSelectorFromString("endSheet:returnCode:"), sheet, code)
                }
                return block
            }
        }
        passThrough(NSApplication.self, "stopModal") { original in
            let call = unsafeBitCast(original, to: StopModalFunction.self)
            let block: @convention(block) (AnyObject) -> Void = { this in
                if sheets.stopModal(response: .stop, reason: "stop_modal") { return }
                call(this, NSSelectorFromString("stopModal"))
            }
            return block
        }
        passThrough(NSApplication.self, "abortModal") { original in
            let call = unsafeBitCast(original, to: StopModalFunction.self)
            let block: @convention(block) (AnyObject) -> Void = { this in
                if sheets.stopModal(response: .abort, reason: "abort_modal") { return }
                call(this, NSSelectorFromString("abortModal"))
            }
            return block
        }
        passThrough(NSApplication.self, "stopModalWithCode:") { original in
            let call = unsafeBitCast(original, to: StopModalWithCodeFunction.self)
            let block: @convention(block) (AnyObject, Int) -> Void = { this, code in
                if sheets.stopModal(response: NSApplication.ModalResponse(rawValue: code), reason: "stop_modal_with_code") { return }
                call(this, NSSelectorFromString("stopModalWithCode:"), code)
            }
            return block
        }

        var unavailablePrivateGuards: [[String: Any]] = []
        func replacePrivate(_ className: String, _ selectorName: String, encoding: String, _ block: Any) {
            let name = "-[\(className) \(selectorName)]"
            guard !installed.contains(name) else { return }
            guard let owner = NSClassFromString(className),
                  let method = class_getInstanceMethod(owner, NSSelectorFromString(selectorName)) else {
                unavailablePrivateGuards.append(["method": name, "reason": "missing"])
                return
            }
            let found = method_getTypeEncoding(method).map { String(cString: $0) } ?? ""
            guard found == encoding else {
                unavailablePrivateGuards.append(["method": name, "reason": "type encoding \(found) differs from \(encoding)"])
                return
            }
            method_setImplementation(method, imp_implementationWithBlock(block))
            installed.append(name)
        }
        let popUpMenuImplementation: @convention(block) (AnyObject, NSMenu, NSPoint, CGFloat, NSView?, AnyObject?, NSFont?, NSRect, UInt, AnyObject?) -> Void = { _, menu, location, width, view, _, _, positioningRect, _, _ in
            if let view, !positioningRect.isEmpty {
                _ = presentMenu(menu, window: view.window, anchor: .below(view.convert(positioningRect, to: nil)), minimumWidth: width, source: "swiftui_menu")
            } else {
                let (window, point) = windowPoint(location, in: view)
                _ = presentMenu(menu, window: window, anchor: .item(nil, topLeft: point), minimumWidth: width, source: "swiftui_menu")
            }
        }
        let popUpMenuWithSelectedItem: @convention(block) (AnyObject, NSMenu, NSPoint, CGFloat, NSView?, Int, NSFont?) -> Void = { _, menu, location, width, view, selectedIndex, _ in
            let (window, point) = windowPoint(location, in: view)
            let item = selectedIndex >= 0 && selectedIndex < menu.numberOfItems ? menu.item(at: selectedIndex) : nil
            _ = presentMenu(menu, window: window, anchor: .item(item, topLeft: point), minimumWidth: width, source: "swiftui_menu")
        }
        replacePrivate("NSCocoaMenuImpl", "popUpMenu:atLocation:width:view:selectedItemIndexProvider:font:positioningRect:flags:options:",
                       encoding: "v120@0:8@16{CGPoint=dd}24d40@48@?56@64{CGRect={CGPoint=dd}{CGSize=dd}}72Q104@112", popUpMenuImplementation)
        replacePrivate("NSCocoaMenuImpl", "popUpMenu:atLocation:width:forView:withSelectedItem:withFont:",
                       encoding: "v72@0:8@16{CGPoint=dd}24d40@48q56@64", popUpMenuWithSelectedItem)
        let showMenuForEvent: @convention(block) (NSView, NSEvent) -> Bool = { view, event in
            guard let menu = view.menu(for: event) else { return false }
            let window = view.window
            let point = event.window === window ? event.locationInWindow : window.map { $0.convertPoint(fromScreen: NSEvent.mouseLocation) } ?? .zero
            return presentMenu(menu, window: window, anchor: .item(nil, topLeft: point), source: "context_menu_right_click")
        }
        replacePrivate("NSView", "_showMenuForEvent:", encoding: "B24@0:8@16", showMenuForEvent)
        let activateWithInfo: @convention(block) (NSApplication, AnyObject?) -> Void = { _, information in
            blocked("application_activation", ["method": "_activateWithInfo:", "information": information.map { String(describing: type(of: $0)) } ?? NSNull()])
        }
        replacePrivate("NSApplication", "_activateWithInfo:", encoding: "v24@0:8@16", activateWithInfo)
        if !unavailablePrivateGuards.isEmpty {
            LiveStateLog.event("private_guards_unavailable", ["methods": unavailablePrivateGuards])
        }

        if menuObservers.isEmpty {
            menuObservers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: nil) { notification in
                nonisolated(unsafe) let object = notification.object
                MainActor.assumeIsolated {
                    guard let menu = object as? NSMenu else { return }
                    var fields = menuFields(menu)
                    fields["presentingFrames"] = Array(Thread.callStackSymbols.filter { $0.contains("Menu") || $0.contains("PopUp") }.prefix(8))
                    fields["runLoopMode"] = RunLoop.current.currentMode?.rawValue ?? ""
                    let cancellation = LiveStateMenuTrackingCancellation(menu: menu, fields: fields)
                    DispatchQueue.main.async { MainActor.assumeIsolated { cancellation.cancel(through: "main_queue") } }
                    RunLoop.main.perform(inModes: [.common, .eventTracking, .modalPanel, .default]) { MainActor.assumeIsolated { cancellation.cancel(through: "run_loop_perform") } }
                    let timer = Timer(timeInterval: 0.05, repeats: false) { _ in MainActor.assumeIsolated { cancellation.cancel(through: "run_loop_timer") } }
                    for mode in [RunLoop.Mode.common, .eventTracking, .modalPanel, .default] { RunLoop.main.add(timer, forMode: mode) }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        MainActor.assumeIsolated { orderOutWindowsOutsideStage(reason: "menu_tracking_cancelled") }
                    }
                }
            })
            menuObservers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { orderOutWindowsOutsideStage(reason: "menu_tracking_ended") }
            })
        }

        LiveStateLog.event("interaction_guards_installed", ["methods": installed, "missing": missing])
        return missing
    }

    static func orderOutWindowsOutsideStage(reason: String) {
        let stage = stageWindows()
        for window in NSApp.windows where window.isVisible && !stage.contains(ObjectIdentifier(window)) {
            window.orderOut(nil)
            LiveStateLog.event("window_outside_stage_ordered_out", [
                "class": String(describing: type(of: window)), "windowNumber": window.windowNumber, "reason": reason,
            ])
        }
    }

    static func modalCompletion(_ completion: (@convention(block) (Int) -> Void)?) -> (@MainActor (NSApplication.ModalResponse) -> Void)? {
        guard let completion else { return nil }
        return { response in completion(response.rawValue) }
    }

    static func cancellationResponse(of alert: NSAlert) -> Int {
        let buttons = alert.buttons.map(\.keyEquivalent)
        guard let index = buttons.firstIndex(of: "\u{1b}") else { return NSApplication.ModalResponse.abort.rawValue }
        return NSApplication.ModalResponse.alertFirstButtonReturn.rawValue + index
    }

    static func alertFields(_ alert: NSAlert, response: Int) -> [String: Any] {
        ["messageText": alert.messageText, "buttons": alert.buttons.map(\.title), "response": response]
    }

    static func menuFields(_ menu: NSMenu) -> [String: Any] {
        ["menu": menu.title, "items": menu.numberOfItems]
    }

    static func blocked(_ interaction: String, _ fields: [String: Any]) {
        var record = fields
        record["interaction"] = interaction
        LiveStateLog.event("interaction_blocked", record)
    }
}

extension LiveStateInteractionGuards {
    static func windowPoint(_ location: NSPoint, in view: NSView?) -> (NSWindow?, NSPoint) {
        if let view { return (view.window, view.convert(location, to: nil)) }
        let stage = stageWindows()
        let window = NSApp.windows.first { $0.isVisible && stage.contains(ObjectIdentifier($0)) && $0.frame.contains(location) }
        return (window, window?.convertPoint(fromScreen: location) ?? location)
    }

    static func presentMenu(_ menu: NSMenu, window: NSWindow?, anchor: LiveStateMenuAnchor, minimumWidth: CGFloat = 0, source: String) -> Bool {
        guard let window, stageWindows().contains(ObjectIdentifier(window)) else {
            var fields = menuFields(menu)
            fields["reason"] = "The menu was requested for a window that is not a window of the presented state."
            blocked(source, fields)
            return false
        }
        let presented = LiveStateMenuPresenter.shared.present(menu, in: window, anchor: anchor, minimumWidth: minimumWidth, source: source)
        if !presented { blocked(source, menuFields(menu)) }
        return presented
    }
}

@MainActor
final class LiveStateMenuTrackingCancellation {
    private let menu: NSMenu
    private let fields: [String: Any]
    private var isCancelled = false

    init(menu: NSMenu, fields: [String: Any]) {
        self.menu = menu
        self.fields = fields
    }

    func cancel(through channel: String) {
        guard !isCancelled else { return }
        isCancelled = true
        menu.cancelTracking()
        var record = fields
        record["channel"] = channel
        record["runLoopModeAtCancel"] = RunLoop.current.currentMode?.rawValue ?? ""
        LiveStateInteractionGuards.blocked("menu_tracking_cancelled", record)
    }
}
