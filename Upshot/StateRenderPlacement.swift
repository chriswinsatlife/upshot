import AppKit
import SwiftUI

enum StateRenderAppWindow {
    case settings
    case library
    case annotate
    case studio
    case quickLook
    case gallery

    var title: String {
        switch self {
        case .settings: "Settings"
        case .library: "Upshot Library"
        case .annotate: "Upshot Annotate"
        case .studio: "Upshot Recording Editor"
        case .quickLook: "Release Overview.png"
        case .gallery: "Interface Style Gallery"
        }
    }

    var contentSize: CGSize {
        switch self {
        case .settings: CGSize(width: 700, height: 540)
        case .library: CGSize(width: 1180, height: 760)
        case .annotate: CGSize(width: 1100, height: 760)
        case .studio: CGSize(width: 1360, height: 860)
        case .quickLook: CGSize(width: 900, height: 650)
        case .gallery: CGSize(width: 1380, height: 900)
        }
    }

    var contextState: String {
        switch self {
        case .settings: "settings-general"
        case .library: "library-grid"
        case .annotate: "annotation-tool-arrow"
        case .studio: "studio-look"
        case .quickLook: "quick-look-screenshot"
        case .gallery: "design-gallery"
        }
    }
}

struct StateRenderPanel {
    var hasShadow = false
    let frame: (_ fittingSize: CGSize) throws -> CGRect
}

enum StateRenderPopoverAnchor {
    case toolbarTrailing
    case footerTrailing
    case inspectorLeading(y: CGFloat)
    case inspectorTop(x: CGFloat, y: CGFloat)

    func rect(in bounds: CGRect) -> CGRect {
        switch self {
        case .toolbarTrailing: CGRect(x: bounds.maxX - 66, y: bounds.maxY - 46, width: 28, height: 28)
        case .footerTrailing: CGRect(x: bounds.maxX - 112, y: 14, width: 80, height: 28)
        case .inspectorLeading(let y): CGRect(x: bounds.maxX - 330, y: bounds.maxY - y, width: 24, height: 24)
        case .inspectorTop(let x, let y): CGRect(x: x, y: bounds.maxY - y, width: 64, height: 56)
        }
    }

    var edge: NSRectEdge {
        switch self {
        case .toolbarTrailing: .minY
        case .footerTrailing: .maxY
        case .inspectorLeading: .minX
        case .inspectorTop: .minY
        }
    }
}

enum StateRenderScroll {
    case top
    case fraction(CGFloat)
    case frames
}

enum StateRenderPlacement {
    case window(StateRenderAppWindow)
    case panel(StateRenderPanel)
    case display
    case alert(context: String?)
    case popover(context: String, anchor: StateRenderPopoverAnchor)
    case panelOverContext(context: String, panel: (_ contextFrame: CGRect) -> StateRenderPanel)
    case panelOverDisplay(backdrop: () throws -> AnyView, panel: StateRenderPanel)

    static func resolve(name: String, scrollFraction: CGFloat?) -> (StateRenderPlacement, StateRenderScroll) {
        let scroll: StateRenderScroll = scrollFraction.map { .fraction($0) } ?? .top
        if name.hasPrefix("settings-") { return (.window(.settings), .frames) }
        if name.hasPrefix("library-") { return (.window(.library), scroll) }
        if name == "design-gallery" { return (.window(.gallery), .frames) }
        if name.hasPrefix("quick-look-") { return (.window(.quickLook), scroll) }
        switch name {
        case "background-picker": return (.popover(context: "annotation-border", anchor: .inspectorLeading(y: 330)), scroll)
        case "annotation-new-style": return (.popover(context: "annotation-tool-arrow", anchor: .inspectorTop(x: 0, y: 200)), scroll)
        case "studio-new-style": return (.popover(context: "studio-look", anchor: .inspectorTop(x: 0, y: 220)), scroll)
        case "share-options": return (.popover(context: "annotation-tool-arrow", anchor: .toolbarTrailing), scroll)
        case "studio-audio-export": return (.popover(context: "studio-audio", anchor: .inspectorTop(x: 0, y: 420)), scroll)
        default: break
        }
        if name.hasPrefix("studio-export-options-") { return (.popover(context: "studio-look", anchor: .footerTrailing), scroll) }
        if name == "annotation-background" { return (.window(.annotate), .frames) }
        if name.hasPrefix("annotation-") { return (.window(.annotate), scroll) }
        if name.hasPrefix("studio-") { return (.window(.studio), scroll) }
        if name.hasPrefix("alert-") { return (.alert(context: StateRenderAlertContexts.context(for: name)), scroll) }
        if name.hasPrefix("selector-") || name.hasPrefix("recording-source-") || name.hasPrefix("recording-area-") || name == "recording-live-pen" {
            return (.display, scroll)
        }
        if name.hasPrefix("quick-access-") {
            return (.panel(StateRenderPanel { _ in
                CaptureShelfPresenter.panelFrame(visibleFrame: try StateRenderDisplay.visibleFrame, position: UpshotPreferences.previewPosition)
            }), scroll)
        }
        if name.hasPrefix("pinned-") {
            return (.panel(StateRenderPanel(hasShadow: UpshotPreferences.pinnedScreenshotShadow) { size in
                CGRect(origin: PinnedScreenshotPresenter.cascadedOrigin(for: size, visibleFrame: try StateRenderDisplay.visibleFrame, index: 0), size: size)
            }), scroll)
        }
        if name.hasPrefix("history-") {
            return (.panel(StateRenderPanel(hasShadow: true) { _ in
                CaptureHistoryPresenter.panelFrame(screenFrame: try StateRenderDisplay.frame, visibleFrame: try StateRenderDisplay.visibleFrame)
            }), scroll)
        }
        if name.hasPrefix("recording-bar-") {
            let bar = StateRenderPanel { _ in RecordingBarPresenter.panelFrame(visibleFrame: try StateRenderDisplay.visibleFrame) }
            if name.hasPrefix("recording-bar-picker-area") || name.hasPrefix("recording-bar-flyout") {
                return (.panelOverDisplay(backdrop: { try StateRenderDesktop.recordingAreaBackdrop() }, panel: bar), scroll)
            }
            return (.panel(bar), scroll)
        }
        if name.hasPrefix("countdown-") {
            return (.panel(StateRenderPanel { size in
                CGRect(origin: CaptureCountdownPresenter.centeredOrigin(size: size, screenFrame: try StateRenderDisplay.frame), size: size)
            }), scroll)
        }
        if name.hasPrefix("capture-text-") {
            return (.panel(StateRenderPanel { size in
                CGRect(origin: CaptureTextFeedbackPresenter.origin(size: size, visibleFrame: try StateRenderDisplay.visibleFrame), size: size)
            }), scroll)
        }
        if name.hasPrefix("capture-code-") {
            return (.panel(StateRenderPanel(hasShadow: true) { size in
                CGRect(origin: CaptureCodeFeedbackPresenter.origin(size: size, visibleFrame: try StateRenderDisplay.visibleFrame), size: size)
            }), scroll)
        }
        if name.hasPrefix("teleprompter-") {
            return (.panel(StateRenderPanel { size in
                let frame = try StateRenderDisplay.frame
                return CGRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height, width: size.width, height: size.height)
            }), scroll)
        }
        if name == "recording-camera-preview" {
            return (.panel(StateRenderPanel(hasShadow: true) { _ in CameraRecordingManager.previewFrame(visibleFrame: try StateRenderDisplay.visibleFrame) }), scroll)
        }
        if name.hasPrefix("scrolling-capture-") {
            return (.panelOverContext(context: "library-grid") { contextFrame in
                StateRenderPanel { size in
                    ScrollingCaptureControlPanel.panelFrame(size: size, around: contextFrame, visibleFrame: try StateRenderDisplay.visibleFrame)
                }
            }, scroll)
        }
        if name.hasPrefix("menu-") {
            return (.panel(StateRenderPanel { size in
                let visible = try StateRenderDisplay.visibleFrame
                let room = MenuBarMenuRenderView.shadowRoom
                return CGRect(x: visible.maxX - size.width - 96 + room, y: visible.maxY + room - 2 - size.height, width: size.width, height: size.height)
            }), scroll)
        }
        return (.panel(StateRenderPanel { size in
            let frame = try StateRenderDisplay.frame
            return CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
        }), scroll)
    }
}

enum StateRenderAlertContexts {
    static func context(for name: String) -> String? {
        let state = name.dropFirst("alert-".count)
        if state.hasPrefix("editor-unsaved") || state.hasPrefix("annotation-") || state.hasPrefix("style-") || state.hasPrefix("watermark-") {
            return "annotation-tool-arrow"
        }
        if state.hasPrefix("library-") || state == "cloud-delete" { return "library-grid" }
        if state.hasPrefix("studio-") || state == "recording-camera-export-error" || state == "recording-project-save-error" { return "studio-look" }
        return nil
    }
}
