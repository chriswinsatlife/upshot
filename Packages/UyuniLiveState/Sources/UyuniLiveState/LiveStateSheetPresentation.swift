import AppKit

@MainActor
final class LiveStateSheet {
    enum Kind: String {
        case alertSheet = "alert_sheet"
        case windowSheet = "window_sheet"
        case modalAlert = "alert_modal_session"
        case modalWindow = "window_modal_session"

        var isApplicationModal: Bool { self == .modalAlert || self == .modalWindow }
    }

    let kind: Kind
    let host: NSWindow
    let source: NSWindow
    let content: NSView
    let container: NSView
    let frameInWindow: NSRect
    let cancelResponse: NSApplication.ModalResponse
    let placement: String
    var completion: (@MainActor (NSApplication.ModalResponse) -> Void)?
    var response: NSApplication.ModalResponse?
    var alertTarget: LiveStateAlertButtonTarget?
    let previousFirstResponder: NSResponder?
    var redirectedView: NSView?
    var redirectedClass: AnyClass?

    init(kind: Kind, host: NSWindow, source: NSWindow, content: NSView, container: NSView, frameInWindow: NSRect,
         cancelResponse: NSApplication.ModalResponse, placement: String, previousFirstResponder: NSResponder?) {
        self.kind = kind
        self.host = host
        self.source = source
        self.content = content
        self.container = container
        self.frameInWindow = frameInWindow
        self.cancelResponse = cancelResponse
        self.placement = placement
        self.previousFirstResponder = previousFirstResponder
    }

    func contains(screenPoint: NSPoint) -> Bool {
        frameInWindow.contains(host.convertPoint(fromScreen: screenPoint))
    }
}

@MainActor
final class LiveStateSheetPresenter {
    static let shared = LiveStateSheetPresenter()
    static let topInset: CGFloat = 24
    static let windowMargin: CGFloat = 4
    static let cornerRadius: CGFloat = 22

    private(set) var active: LiveStateSheet?
    var stageContains: (NSWindow) -> Bool = { _ in false }
    var modalHostProvider: () -> NSWindow? = { nil }

    var isShowing: Bool { active != nil }

    func presentAlertSheet(_ alert: NSAlert, for window: NSWindow, completion: (@MainActor (NSApplication.ModalResponse) -> Void)?) -> Bool {
        guard let sheet = makeAlertSheet(alert, kind: .alertSheet, host: window) else { return false }
        sheet.completion = completion
        return true
    }

    func runModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse? {
        guard let host = modalHostProvider(), let sheet = makeAlertSheet(alert, kind: .modalAlert, host: host) else { return nil }
        return runModalLoop(sheet)
    }

    func presentWindowSheet(_ source: NSWindow, for window: NSWindow, completion: (@MainActor (NSApplication.ModalResponse) -> Void)?) -> Bool {
        guard let sheet = makeWindowSheet(source, kind: .windowSheet, host: window) else { return false }
        sheet.completion = completion
        return true
    }

    func runModalWindow(_ source: NSWindow) -> NSApplication.ModalResponse? {
        guard let host = modalHostProvider(), let sheet = makeWindowSheet(source, kind: .modalWindow, host: host) else { return nil }
        return runModalLoop(sheet)
    }

    func endSheet(_ source: NSWindow, response: NSApplication.ModalResponse) -> Bool {
        guard let sheet = active, sheet.source === source else { return false }
        end(sheet, response: response, reason: "end_sheet")
        return true
    }

    func stopModal(response: NSApplication.ModalResponse, reason: String) -> Bool {
        guard let sheet = active, sheet.kind == .modalWindow else { return false }
        end(sheet, response: response, reason: reason)
        return true
    }

    func close(reason: String) {
        guard let sheet = active else { return }
        end(sheet, response: sheet.cancelResponse, reason: reason)
    }

    func blocks(_ window: NSWindow, screenPoint: NSPoint) -> Bool {
        guard let sheet = active else { return false }
        if sheet.host === window { return !sheet.contains(screenPoint: screenPoint) }
        return sheet.kind.isApplicationModal
    }

    func modalHitView(at screenPoint: NSPoint) -> NSView? {
        guard let sheet = active, sheet.kind.isApplicationModal, sheet.contains(screenPoint: screenPoint), let superview = sheet.container.superview else { return nil }
        let point = superview.convert(sheet.host.convertPoint(fromScreen: screenPoint), from: nil)
        return sheet.container.hitTest(point)
    }

    func keyWindow() -> NSWindow? { active?.host }

    func performKey(_ event: NSEvent) -> Bool {
        guard let sheet = active else { return false }
        let characters = event.charactersIgnoringModifiers ?? ""
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if let button = Self.buttons(in: sheet.container).first(where: { button in
            button.isEnabled && !button.isHidden && !button.keyEquivalent.isEmpty && button.keyEquivalent == characters
                && button.keyEquivalentModifierMask.intersection([.command, .option, .control, .shift]) == modifiers
        }) {
            LiveStateLog.event("sheet_key_equivalent", ["kind": sheet.kind.rawValue, "button": button.title, "characters": characters.unicodeScalars.map(\.value)])
            button.performClick(nil)
            return true
        }
        return sheet.container.performKeyEquivalent(with: event)
    }

    private static func buttons(in view: NSView) -> [NSButton] {
        view.subviews.flatMap { subview in (subview as? NSButton).map { [$0] } ?? [] } + view.subviews.flatMap { buttons(in: $0) }
    }

    private func makeAlertSheet(_ alert: NSAlert, kind: LiveStateSheet.Kind, host: NSWindow) -> LiveStateSheet? {
        guard active == nil else { return unavailable(kind, "Another sheet is shown in the state.") }
        alert.layout()
        let source = alert.window
        guard let content = source.contentView else { return unavailable(kind, "The alert window has no content view.") }
        let cancel = NSApplication.ModalResponse(rawValue: LiveStateInteractionGuards.cancellationResponse(of: alert))
        guard let sheet = install(content: content, size: source.frame.size, kind: kind, host: host, source: source, cancelResponse: cancel,
                                  firstResponder: nil, fields: LiveStateInteractionGuards.alertFields(alert, response: cancel.rawValue)) else { return nil }
        sheet.alertTarget = LiveStateAlertButtonTarget(alert: alert, removesWindow: false) { [weak self, weak sheet] response in
            guard let self, let sheet else { return }
            end(sheet, response: response, reason: "button")
        }
        return sheet
    }

    private func makeWindowSheet(_ source: NSWindow, kind: LiveStateSheet.Kind, host: NSWindow) -> LiveStateSheet? {
        guard active == nil else { return unavailable(kind, "Another sheet is shown in the state.") }
        guard let content = source.contentView else { return unavailable(kind, "The sheet window has no content view.") }
        content.layoutSubtreeIfNeeded()
        var size = source.contentLayoutRect.size
        if size.width < 1 || size.height < 1 { size = content.frame.size }
        if size.width < 1 || size.height < 1 { size = content.fittingSize }
        let cancel: NSApplication.ModalResponse = kind == .modalWindow ? .abort : .cancel
        return install(content: content, size: size, kind: kind, host: host, source: source, cancelResponse: cancel,
                       firstResponder: source.initialFirstResponder, fields: ["class": String(describing: type(of: source)), "title": source.title])
    }

    private func install(content: NSView, size: CGSize, kind: LiveStateSheet.Kind, host: NSWindow, source: NSWindow,
                         cancelResponse: NSApplication.ModalResponse, firstResponder: NSView?, fields: [String: Any]) -> LiveStateSheet? {
        guard stageContains(host) else { return unavailable(kind, "The sheet was requested for a window that is not a window of the presented state.", fields) }
        guard let hostContentView = host.contentView else { return unavailable(kind, "The window has no content view.", fields) }
        let bounds = hostContentView.convert(hostContentView.bounds, to: nil)
        let layout = host.contentLayoutRect
        var frame = CGRect(x: (bounds.midX - size.width / 2).rounded(), y: (layout.maxY - Self.topInset - size.height).rounded(),
                           width: size.width, height: size.height)
        frame.origin.y = max(frame.minY, bounds.minY + Self.windowMargin)
        guard frame.width <= bounds.width - Self.windowMargin * 2, frame.height <= bounds.height - Self.windowMargin * 2 else {
            var record = fields
            record["sheetSize"] = [Double(size.width), Double(size.height)]
            record["windowSize"] = [Double(bounds.width), Double(bounds.height)]
            return unavailable(kind, "The sheet does not fit inside the window that presents it.", record)
        }
        LiveStateMenuPresenter.shared.close(reason: "sheet_presented")
        let previousFirstResponder = host.firstResponder
        source.contentView = NSView(frame: CGRect(origin: .zero, size: size))
        let container = Self.makeContainer(frame: frame, appearance: host.effectiveAppearance, glass: kind == .alertSheet || kind == .modalAlert)
        content.frame = container.bounds
        content.autoresizingMask = [.width, .height]
        container.addSubview(content)
        hostContentView.addSubview(container, positioned: .above, relativeTo: nil)
        container.frame = hostContentView.convert(frame, from: nil)
        hostContentView.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        var placement = "content_view"
        if LiveStateOverlayLayer.attach(container, to: hostContentView) {
            host.displayIfNeeded()
            placement = "content_view_layer_attached"
        }
        var redirectedClass: AnyClass?
        if !Self.isReachable(container, in: host), container.layer?.superlayer != nil, let original = LiveStateHitTestRedirect.install(on: hostContentView, container: container) {
            if Self.isReachable(container, in: host) {
                redirectedClass = original
                placement = "content_view_with_hit_test"
            } else {
                LiveStateHitTestRedirect.remove(from: hostContentView, restoring: original)
            }
        }
        if !Self.isReachable(container, in: host), let frameView = hostContentView.superview {
            container.removeFromSuperview()
            frameView.addSubview(container, positioned: .above, relativeTo: hostContentView)
            container.frame = frameView.convert(frame, from: nil)
            placement = "frame_view_above_content_view"
        }
        let sheet = LiveStateSheet(kind: kind, host: host, source: source, content: content, container: container, frameInWindow: frame,
                                   cancelResponse: cancelResponse, placement: placement, previousFirstResponder: previousFirstResponder)
        sheet.redirectedView = redirectedClass.map { _ in hostContentView }
        sheet.redirectedClass = redirectedClass
        active = sheet
        if let firstResponder, firstResponder.isDescendant(of: container) {
            host.makeFirstResponder(firstResponder)
        } else if let first = Self.firstKeyView(in: content) {
            host.makeFirstResponder(first)
        } else {
            host.makeFirstResponder(nil)
        }
        host.displayIfNeeded()
        var record = fields
        record["kind"] = kind.rawValue
        record["windowNumber"] = host.windowNumber
        record["frame"] = NSStringFromRect(frame)
        record["placement"] = placement
        record["reachable"] = Self.isReachable(container, in: host)
        LiveStateLog.event("sheet_presented", record)
        return sheet
    }

    private func runModalLoop(_ sheet: LiveStateSheet) -> NSApplication.ModalResponse {
        let begun = ContinuousClock.now
        var events = 0
        while sheet.response == nil {
            autoreleasepool {
                if let event = NSApp.nextEvent(matching: .any, until: Date(timeIntervalSinceNow: 0.05), inMode: .modalPanel, dequeue: true) {
                    events += 1
                    NSApp.sendEvent(event)
                }
            }
        }
        let response = sheet.response ?? sheet.cancelResponse
        LiveStateLog.event("sheet_modal_loop_ended", ["kind": sheet.kind.rawValue, "response": response.rawValue, "events": events,
                                                      "milliseconds": LiveStateLog.milliseconds(since: begun)])
        return response
    }

    private func end(_ sheet: LiveStateSheet, response: NSApplication.ModalResponse, reason: String) {
        guard sheet.response == nil else { return }
        sheet.response = response
        if active === sheet { active = nil }
        sheet.container.removeFromSuperview()
        if let view = sheet.redirectedView, let original = sheet.redirectedClass { LiveStateHitTestRedirect.remove(from: view, restoring: original) }
        sheet.redirectedView = nil
        sheet.content.removeFromSuperview()
        sheet.content.autoresizingMask = []
        sheet.content.frame = CGRect(origin: .zero, size: sheet.frameInWindow.size)
        sheet.source.contentView = sheet.content
        sheet.alertTarget?.release()
        sheet.alertTarget = nil
        if let previous = sheet.previousFirstResponder, (previous as? NSView)?.window === sheet.host || previous === sheet.host {
            sheet.host.makeFirstResponder(previous)
        }
        sheet.host.displayIfNeeded()
        LiveStateLog.event("sheet_ended", ["kind": sheet.kind.rawValue, "response": response.rawValue, "reason": reason, "windowNumber": sheet.host.windowNumber])
        let completion = sheet.completion
        sheet.completion = nil
        completion?(response)
    }

    private func unavailable(_ kind: LiveStateSheet.Kind, _ reason: String, _ fields: [String: Any] = [:]) -> LiveStateSheet? {
        var record = fields
        record["kind"] = kind.rawValue
        record["reason"] = reason
        LiveStateLog.event("sheet_presentation_unavailable", record)
        return nil
    }

    private static func makeContainer(frame: CGRect, appearance: NSAppearance, glass: Bool) -> NSView {
        let container = NSView(frame: frame)
        container.wantsLayer = true
        container.appearance = appearance
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        container.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.5 : 0.25)
            shadow.shadowBlurRadius = 30
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            return shadow
        }()
        let background = NSVisualEffectView(frame: container.bounds)
        background.material = glass ? .popover : .windowBackground
        background.blendingMode = .withinWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = cornerRadius
        background.layer?.cornerCurve = .continuous
        background.layer?.masksToBounds = true
        background.layer?.borderWidth = 0.5
        background.layer?.borderColor = (isDark ? NSColor.white.withAlphaComponent(0.18) : NSColor.black.withAlphaComponent(0.12)).cgColor
        background.autoresizingMask = [.width, .height]
        container.addSubview(background)
        return container
    }

    private static func isReachable(_ container: NSView, in window: NSWindow) -> Bool {
        guard container.layer?.superlayer != nil, let frameView = window.contentView?.superview else { return false }
        let center = container.convert(NSPoint(x: container.bounds.midX, y: container.bounds.midY), to: nil)
        guard let hit = frameView.hitTest(frameView.convert(center, from: nil)) else { return false }
        return hit === container || hit.isDescendant(of: container)
    }

    private static func firstKeyView(in view: NSView) -> NSView? {
        for subview in view.subviews {
            if let field = subview as? NSTextField, field.isEditable { return field }
            if let found = firstKeyView(in: subview) { return found }
        }
        return nil
    }
}

@MainActor
enum LiveStateHitTestRedirect {
    private static var subclasses: [String: AnyClass] = [:]
    nonisolated(unsafe) private static var containers: [ObjectIdentifier: NSView] = [:]

    static func install(on view: NSView, container: NSView) -> AnyClass? {
        guard let original = object_getClass(view) else { return nil }
        let originalName = NSStringFromClass(original)
        let subclass: AnyClass
        if let existing = subclasses[originalName] {
            subclass = existing
        } else {
            let selector = #selector(NSView.hitTest(_:))
            guard let method = class_getInstanceMethod(original, selector),
                  let made = objc_allocateClassPair(original, "UyuniLiveStateSheetHitTest_\(originalName)", 0) else { return nil }
            typealias HitTestFunction = @convention(c) (AnyObject, Selector, NSPoint) -> NSView?
            let callOriginal = unsafeBitCast(method_getImplementation(method), to: HitTestFunction.self)
            let hitTest: @convention(block) (NSView, NSPoint) -> NSView? = { this, point in
                if let container = containers[ObjectIdentifier(this)], container.superview === this,
                   let hit = container.hitTest(this.convert(point, from: this.superview)) {
                    return hit
                }
                return callOriginal(this, selector, point)
            }
            class_addMethod(made, selector, imp_implementationWithBlock(hitTest), method_getTypeEncoding(method))
            objc_registerClassPair(made)
            subclasses[originalName] = made
            subclass = made
        }
        containers[ObjectIdentifier(view)] = container
        object_setClass(view, subclass)
        return original
    }

    static func remove(from view: NSView, restoring original: AnyClass) {
        containers.removeValue(forKey: ObjectIdentifier(view))
        object_setClass(view, original)
    }
}
