import AppKit
import SwiftUI

struct AnnotationCanvasInputHandler: NSViewRepresentable {
    let onPan: (CGFloat, CGFloat) -> Void
    let onZoom: (CGFloat, CGPoint) -> Void
    let onBeginPinch: (CGPoint) -> Void
    let onPinch: (CGFloat) -> Void
    let onEndPinch: () -> Void
    let onOptionChanged: (Bool) -> Void

    func makeNSView(context: Context) -> InputView {
        let view = InputView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: InputView, context: Context) {
        view.onPan = onPan
        view.onZoom = onZoom
        view.onBeginPinch = onBeginPinch
        view.onPinch = onPinch
        view.onEndPinch = onEndPinch
        view.onOptionChanged = onOptionChanged
    }

    static func dismantleNSView(_ view: InputView, coordinator: ()) { view.detach() }

    final class InputView: NSView, NSGestureRecognizerDelegate {
        var onPan: ((CGFloat, CGFloat) -> Void)?
        var onZoom: ((CGFloat, CGPoint) -> Void)?
        var onBeginPinch: ((CGPoint) -> Void)?
        var onPinch: ((CGFloat) -> Void)?
        var onEndPinch: (() -> Void)?
        var onOptionChanged: ((Bool) -> Void)?

        private lazy var magnifier: NSMagnificationGestureRecognizer = {
            let recognizer = NSMagnificationGestureRecognizer(target: self, action: #selector(magnifyCanvas(_:)))
            recognizer.delegate = self
            return recognizer
        }()
        private var scrollMonitor: Any?
        private var suppressScrollMomentum = false

        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detach()
            guard let root = window?.contentView else { return }
            root.addGestureRecognizer(magnifier)
            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .flagsChanged]) { [weak self] event in
                guard let self else { return event }
                if event.type == .flagsChanged {
                    if self.window?.isKeyWindow == true {
                        self.onOptionChanged?(event.modifierFlags.contains(.option))
                    }
                    return event
                }
                return self.handleScroll(event)
            }
        }

        func detach() {
            magnifier.view?.removeGestureRecognizer(magnifier)
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
            scrollMonitor = nil
            onEndPinch?()
            suppressScrollMomentum = false
        }

        deinit {
            if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: NSGestureRecognizer) -> Bool {
            guard let window, window.isKeyWindow, !(window.firstResponder is NSTextView) else { return false }
            return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
        }

        @objc private func magnifyCanvas(_ recognizer: NSMagnificationGestureRecognizer) {
            switch recognizer.state {
            case .began:
                guard let window else { return }
                let anchor = convert(window.mouseLocationOutsideOfEventStream, from: nil)
                suppressScrollMomentum = true
                onBeginPinch?(anchor)
                onPinch?(AnnotationCanvasViewport.pinchFactor(for: recognizer.magnification))
            case .changed:
                onPinch?(AnnotationCanvasViewport.pinchFactor(for: recognizer.magnification))
            case .ended:
                onPinch?(AnnotationCanvasViewport.pinchFactor(for: recognizer.magnification))
                onEndPinch?()
            case .cancelled, .failed:
                onEndPinch?()
            default:
                break
            }
        }

        private func handleScroll(_ event: NSEvent) -> NSEvent? {
            guard let window, event.window == window, window.isKeyWindow,
                  !(window.firstResponder is NSTextView) else { return event }
            let anchor = convert(event.locationInWindow, from: nil)
            guard bounds.contains(anchor) else { return event }
            guard magnifier.state != .began, magnifier.state != .changed else { return nil }
            if suppressScrollMomentum {
                if !event.momentumPhase.isEmpty { return nil }
                if event.phase.contains(.began) || !event.hasPreciseScrollingDeltas {
                    suppressScrollMomentum = false
                } else {
                    return nil
                }
            }
            if event.modifierFlags.intersection([.command, .option]).isEmpty {
                onPan?(event.scrollingDeltaX, event.scrollingDeltaY)
            } else {
                onZoom?(exp(event.scrollingDeltaY * 0.0025), anchor)
            }
            return nil
        }
    }
}
