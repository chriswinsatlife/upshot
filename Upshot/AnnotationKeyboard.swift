
import AppKit
import SwiftUI

struct AnnotationKeyCommandHandler: NSViewRepresentable {
    let isEnabled: () -> Bool
    let onDelete: () -> Void
    let onSave: () -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let canUndo: () -> Bool
    let canRedo: () -> Bool
    let canvasFocusRequest: Int
    let onSelectAll: () -> Void
    let onSelectTool: (AnnotationTool) -> Void
    let onZoomIn: () -> Void
    let onZoomOut: () -> Void
    let onFitCanvas: () -> Void
    let onActualSize: () -> Void
    let onToggleCrop: () -> Void
    let onApplyCrop: () -> Void
    let onCancelCrop: () -> Void
    let onNudgeCrop: (CGSize) -> Void
    let isCropping: () -> Bool

    func makeNSView(context: Context) -> AnnotationKeyCommandHandlerView {
        let view = AnnotationKeyCommandHandlerView()
        apply(to: view)
        return view
    }

    func updateNSView(_ nsView: AnnotationKeyCommandHandlerView, context: Context) {
        apply(to: nsView)
    }

    private func apply(to view: AnnotationKeyCommandHandlerView) {
        view.isEnabled = isEnabled
        view.onDelete = onDelete
        view.onSave = onSave
        view.onUndo = onUndo
        view.onRedo = onRedo
        view.canUndo = canUndo
        view.canRedo = canRedo
        view.onSelectAll = onSelectAll
        view.onSelectTool = onSelectTool
        view.onZoomIn = onZoomIn
        view.onZoomOut = onZoomOut
        view.onFitCanvas = onFitCanvas
        view.onActualSize = onActualSize
        view.onToggleCrop = onToggleCrop
        view.onApplyCrop = onApplyCrop
        view.onCancelCrop = onCancelCrop
        view.onNudgeCrop = onNudgeCrop
        view.isCropping = isCropping
        if view.canvasFocusRequest != canvasFocusRequest {
            view.canvasFocusRequest = canvasFocusRequest
            view.takeKeyboardFocusFromInspector()
        }
    }
}

final class AnnotationKeyCommandHandlerView: NSView, NSMenuItemValidation {
    var isEnabled: (() -> Bool)?
    var onDelete: (() -> Void)?
    var onSave: (() -> Void)?
    var onUndo: (() -> Void)?
    var onRedo: (() -> Void)?
    var canUndo: (() -> Bool)?
    var canRedo: (() -> Bool)?
    var canvasFocusRequest = 0
    var onSelectAll: (() -> Void)?
    var onSelectTool: ((AnnotationTool) -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?
    var onFitCanvas: (() -> Void)?
    var onActualSize: (() -> Void)?
    var onToggleCrop: (() -> Void)?
    var onApplyCrop: (() -> Void)?
    var onCancelCrop: (() -> Void)?
    var onNudgeCrop: ((CGSize) -> Void)?
    var isCropping: (() -> Bool)?

    private var localKeyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLocalKeyMonitor()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.window, window.firstResponder === window else { return }
            window.makeFirstResponder(self)
        }
    }

    func takeKeyboardFocusFromInspector() {
        guard let window, window.firstResponder !== self,
              !(window.firstResponder is AnnoTextEditorOverlay) else { return }
        let previous = window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"
        let accepted = window.makeFirstResponder(self)
        AppLog.event("annotation", "annotation_canvas_keyboard_focus", fields: ["previous": previous, "outcome": accepted ? "taken" : "refused"])
    }

    @objc func undo(_ sender: Any?) {
        onUndo?()
    }

    @objc func redo(_ sender: Any?) {
        onRedo?()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(undo(_:)):
            return isEnabled?() != false && canUndo?() == true
        case #selector(redo(_:)):
            return isEnabled?() != false && canRedo?() == true
        default:
            return true
        }
    }

    deinit {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
        }
    }

    private func updateLocalKeyMonitor() {
        guard localKeyMonitor == nil else { return }

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.window?.isKeyWindow == true else {
                return event
            }

            guard self.isEnabled?() != false else { return nil }

            if Self.isSave(event) {
                self.onSave?()
                return nil
            }

            if Self.isEditingText(in: self.window) {
                return event
            }

            if self.isCropping?() == true {
                if Self.isReturn(event) {
                    self.onApplyCrop?()
                    return nil
                }
                if Self.isEscape(event) {
                    self.onCancelCrop?()
                    return nil
                }
                if let delta = Self.arrowNudge(event) {
                    self.onNudgeCrop?(delta)
                    return nil
                }
                if Self.isUndo(event) || Self.isRedo(event) {
                    return event
                }
                return nil
            }

            if Self.isCropToggle(event) {
                self.onToggleCrop?()
                return nil
            }

            if Self.isPlainDelete(event) {
                self.onDelete?()
                return nil
            }

            if Self.isUndo(event) {
                self.onUndo?()
                return nil
            }

            if Self.isRedo(event) {
                self.onRedo?()
                return nil
            }

            if Self.isSelectAll(event) {
                self.onSelectAll?()
                return nil
            }

            if Self.isZoomIn(event) {
                self.onZoomIn?()
                return nil
            }

            if Self.isZoomOut(event) {
                self.onZoomOut?()
                return nil
            }

            if Self.isFitCanvas(event) {
                self.onFitCanvas?()
                return nil
            }

            if Self.isActualSize(event) {
                self.onActualSize?()
                return nil
            }

            if let tool = Self.toolShortcut(for: event) {
                self.onSelectTool?(tool)
                return nil
            }

            return event
        }
    }

    private static func isPlainDelete(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            && (event.keyCode == 51 || event.keyCode == 117)
    }

    private static func isReturn(_ event: NSEvent) -> Bool {
        event.keyCode == 36 || event.keyCode == 76
    }

    private static func isEscape(_ event: NSEvent) -> Bool {
        event.keyCode == 53
    }

    static func arrowNudge(_ event: NSEvent) -> CGSize? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return nil }
        let step: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: return CGSize(width: -step, height: 0)
        case 124: return CGSize(width: step, height: 0)
        case 125: return CGSize(width: 0, height: step)
        case 126: return CGSize(width: 0, height: -step)
        default: return nil
        }
    }

    private static func isCropToggle(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .option, .control]).isEmpty
            && event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    private static func isEditingText(in window: NSWindow?) -> Bool {
        window?.firstResponder is NSTextView
    }

    private static func isSave(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && !event.modifierFlags.contains(.option)
            && event.charactersIgnoringModifiers?.lowercased() == "s"
    }

    private static func isUndo(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "z"
    }

    private static func isRedo(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "z"
    }

    private static func isSelectAll(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers?.lowercased() == "a"
    }

    private static func isZoomIn(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.contains(.command) else { return false }
        let character = event.charactersIgnoringModifiers
        return character == "+" || character == "="
    }

    private static func isZoomOut(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && (event.charactersIgnoringModifiers == "-" || event.charactersIgnoringModifiers == "_")
    }

    private static func isFitCanvas(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers == "1"
    }

    private static func isActualSize(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
            && !event.modifierFlags.contains(.shift)
            && event.charactersIgnoringModifiers == "0"
    }

    private static func toolShortcut(for event: NSEvent) -> AnnotationTool? {
        guard event.modifierFlags.intersection([.command, .option, .control]).isEmpty,
              let character = event.charactersIgnoringModifiers?.lowercased(),
              character.count == 1 else {
            return nil
        }

        switch character {
        case "r": return .rectangle
        case "o": return .ellipse
        case "t": return .text
        case "l": return .line
        case "a": return .arrow
        case "p": return .pixelate
        case "b": return .blur
        case "1": return .numberedCircle
        case "h": return .select
        default: return nil
        }
    }
}
