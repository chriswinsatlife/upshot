import AppKit

@MainActor
enum LiveStateMenuAnchor {
    case item(NSMenuItem?, topLeft: NSPoint)
    case below(NSRect)
    case popUpButton(NSPopUpButtonCell, NSRect)

    var name: String {
        switch self {
        case .item(let item, _): item == nil ? "point" : "item"
        case .below: "below_rect"
        case .popUpButton(let cell, _): cell.pullsDown ? "pull_down_button" : "pop_up_button"
        }
    }
}

enum LiveStateMenuPointerOutcome: String {
    case chose
    case openedSubmenu = "opened_submenu"
    case highlighted
    case insideMenu = "inside_menu"
    case closedOutside = "closed_outside"
}

enum LiveStateMenuMetrics {
    static let verticalPadding: CGFloat = 5
    static let rowHeight: CGFloat = 24
    static let separatorHeight: CGFloat = 11
    static let headerHeight: CGFloat = 24
    static let highlightInset: CGFloat = 4.5
    static let highlightVerticalInset: CGFloat = 0.5
    static let highlightRadius: CGFloat = 5.5
    static let cornerRadius: CGFloat = 13
    static let stateCenterX: CGFloat = 17.5
    static let titleX: CGFloat = 30
    static let imageWidth: CGFloat = 16
    static let imageGap: CGFloat = 6
    static let indentationStep: CGFloat = 10
    static let trailingPadding: CGFloat = 17
    static let keyEquivalentGap: CGFloat = 28
    static let chevronWidth: CGFloat = 12
    static let windowMargin: CGFloat = 4
    static let popUpTitleInset: CGFloat = 9
    static let submenuOverlap: CGFloat = 4
    static let minimumWidth: CGFloat = 120
    static var font: NSFont { NSFont.menuFont(ofSize: 0) }
    static var headerFont: NSFont { NSFont.menuFont(ofSize: 0) }
    static var checkmark: NSImage? { NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 12, weight: .bold)) }
}

struct LiveStateMenuRow {
    enum Kind { case item, separator, header }
    let kind: Kind
    let item: NSMenuItem
    let top: CGFloat
    let height: CGFloat

    var isSelectable: Bool { kind == .item && item.isEnabled }
    var bottom: CGFloat { top + height }
}

struct LiveStateMenuLayout {
    let rows: [LiveStateMenuRow]
    let size: CGSize
    let titleX: CGFloat

    init(menu: NSMenu, minimumWidth: CGFloat, skipsFirstItem: Bool = false) {
        var items: [NSMenuItem] = []
        for item in menu.items.dropFirst(skipsFirstItem ? 1 : 0) where !item.isHidden && !item.isAlternate {
            if item.isSeparatorItem, items.last?.isSeparatorItem ?? true { continue }
            items.append(item)
        }
        while items.last?.isSeparatorItem == true { items.removeLast() }
        let hasImages = items.contains { !$0.isSeparatorItem && $0.image != nil }
        titleX = LiveStateMenuMetrics.titleX + (hasImages ? LiveStateMenuMetrics.imageWidth + LiveStateMenuMetrics.imageGap : 0)
        var rows: [LiveStateMenuRow] = []
        var y = LiveStateMenuMetrics.verticalPadding
        var width = max(minimumWidth, LiveStateMenuMetrics.minimumWidth)
        for item in items {
            let kind: LiveStateMenuRow.Kind = item.isSeparatorItem ? .separator : item.isSectionHeader ? .header : .item
            var height = kind == .separator ? LiveStateMenuMetrics.separatorHeight : kind == .header ? LiveStateMenuMetrics.headerHeight : LiveStateMenuMetrics.rowHeight
            if kind == .item, let image = item.image { height = max(height, image.size.height + 6) }
            rows.append(LiveStateMenuRow(kind: kind, item: item, top: y, height: height))
            y += height
            guard kind != .separator else { continue }
            let font = kind == .header ? LiveStateMenuMetrics.headerFont : (item.menu?.font ?? LiveStateMenuMetrics.font)
            let titleWidth = Self.title(of: item, font: font, color: .labelColor).size().width
            var rowWidth = titleX + CGFloat(item.indentationLevel) * LiveStateMenuMetrics.indentationStep + ceil(titleWidth) + LiveStateMenuMetrics.trailingPadding
            let keyEquivalent = Self.keyEquivalentText(of: item)
            if !keyEquivalent.isEmpty {
                rowWidth += LiveStateMenuMetrics.keyEquivalentGap + ceil((keyEquivalent as NSString).size(withAttributes: [.font: LiveStateMenuMetrics.font]).width)
            }
            if item.hasSubmenu { rowWidth += LiveStateMenuMetrics.keyEquivalentGap }
            width = max(width, rowWidth)
        }
        self.rows = rows
        size = CGSize(width: ceil(width), height: y + LiveStateMenuMetrics.verticalPadding)
    }

    func rowIndex(atY y: CGFloat) -> Int? {
        rows.firstIndex { y >= $0.top && y < $0.bottom }
    }

    static func title(of item: NSMenuItem, font: NSFont, color: NSColor) -> NSAttributedString {
        if let attributed = item.attributedTitle, attributed.length > 0 {
            let copy = NSMutableAttributedString(attributedString: attributed)
            copy.enumerateAttribute(.foregroundColor, in: NSRange(location: 0, length: copy.length)) { value, range, _ in
                if value == nil { copy.addAttribute(.foregroundColor, value: color, range: range) }
            }
            return copy
        }
        return NSAttributedString(string: item.title, attributes: [.font: font, .foregroundColor: color])
    }

    static func keyEquivalentText(of item: NSMenuItem) -> String {
        let key = item.keyEquivalent
        guard !key.isEmpty else { return "" }
        var flags = item.keyEquivalentModifierMask
        if key.count == 1, let character = key.first, character.isUppercase { flags.insert(.shift) }
        var text = ""
        if flags.contains(.control) { text += "\u{2303}" }
        if flags.contains(.option) { text += "\u{2325}" }
        if flags.contains(.shift) { text += "\u{21E7}" }
        if flags.contains(.command) { text += "\u{2318}" }
        let names: [String: String] = ["\r": "\u{21A9}", "\u{1b}": "\u{238B}", "\t": "\u{21E5}", "\u{7f}": "\u{232B}", "\u{8}": "\u{232B}", " ": "Space"]
        return text + (names[key] ?? key.uppercased())
    }
}

final class LiveStateMenuContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

final class LiveStateMenuRowsView: NSView {
    let presentedMenu: NSMenu
    let layout: LiveStateMenuLayout
    var highlightedRow: Int? { didSet { if highlightedRow != oldValue { needsDisplay = true } } }
    var scrollOffset: CGFloat = 0 { didSet { if scrollOffset != oldValue { needsDisplay = true } } }

    init(menu: NSMenu, layout: LiveStateMenuLayout, frame: NSRect) {
        presentedMenu = menu
        self.layout = layout
        super.init(frame: frame)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let font = LiveStateMenuMetrics.font
        for (index, row) in layout.rows.enumerated() {
            let top = row.top - scrollOffset
            guard top + row.height > 0, top < bounds.height else { continue }
            switch row.kind {
            case .separator:
                NSColor.separatorColor.setFill()
                NSRect(x: layout.titleX, y: (top + row.height / 2).rounded(.down), width: bounds.width - layout.titleX - LiveStateMenuMetrics.trailingPadding, height: 1).fill()
            case .header:
                let title = LiveStateMenuLayout.title(of: row.item, font: LiveStateMenuMetrics.headerFont, color: .tertiaryLabelColor)
                let size = title.size()
                title.draw(at: NSPoint(x: layout.titleX, y: top + (row.height - size.height) / 2))
            case .item:
                let item = row.item
                let highlighted = index == highlightedRow && row.isSelectable
                if highlighted {
                    NSColor.controlAccentColor.setFill()
                    NSBezierPath(roundedRect: NSRect(x: LiveStateMenuMetrics.highlightInset, y: top + LiveStateMenuMetrics.highlightVerticalInset,
                                                     width: bounds.width - LiveStateMenuMetrics.highlightInset * 2, height: row.height - LiveStateMenuMetrics.highlightVerticalInset * 2),
                                 xRadius: LiveStateMenuMetrics.highlightRadius, yRadius: LiveStateMenuMetrics.highlightRadius).fill()
                }
                let textColor: NSColor = highlighted ? .selectedMenuItemTextColor : item.isEnabled ? .labelColor : .tertiaryLabelColor
                let secondaryColor: NSColor = highlighted ? .selectedMenuItemTextColor : .tertiaryLabelColor
                let indent = CGFloat(item.indentationLevel) * LiveStateMenuMetrics.indentationStep
                let defaultCheckmark = item.onStateImage.map { $0.name()?.lowercased().contains("checkmark") ?? false } ?? true
                let stateImage: NSImage? = item.state == .on ? (defaultCheckmark ? LiveStateMenuMetrics.checkmark : item.onStateImage) : item.state == .mixed ? item.mixedStateImage : item.offStateImage
                if let stateImage {
                    let size = Self.fitted(stateImage.size, maximum: 14)
                    draw(stateImage, in: NSRect(x: LiveStateMenuMetrics.stateCenterX - size.width / 2 + indent, y: top + (row.height - size.height) / 2, width: size.width, height: size.height),
                         color: textColor)
                }
                if let image = item.image {
                    let size = Self.fitted(image.size, maximum: LiveStateMenuMetrics.imageWidth)
                    draw(image, in: NSRect(x: LiveStateMenuMetrics.titleX + indent + (LiveStateMenuMetrics.imageWidth - size.width) / 2, y: top + (row.height - size.height) / 2,
                                           width: size.width, height: size.height), color: textColor)
                }
                let title = LiveStateMenuLayout.title(of: item, font: item.menu?.font ?? font, color: textColor)
                let highlightedTitle = NSMutableAttributedString(attributedString: title)
                if highlighted { highlightedTitle.addAttribute(.foregroundColor, value: textColor, range: NSRange(location: 0, length: highlightedTitle.length)) }
                let titleSize = highlightedTitle.size()
                highlightedTitle.draw(at: NSPoint(x: layout.titleX + indent, y: top + (row.height - titleSize.height) / 2))
                let keyEquivalent = LiveStateMenuLayout.keyEquivalentText(of: item)
                if !keyEquivalent.isEmpty {
                    let text = NSAttributedString(string: keyEquivalent, attributes: [.font: font, .foregroundColor: secondaryColor])
                    let size = text.size()
                    text.draw(at: NSPoint(x: bounds.width - LiveStateMenuMetrics.trailingPadding - size.width, y: top + (row.height - size.height) / 2))
                }
                if item.hasSubmenu, let chevron = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
                    .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold)) {
                    let size = chevron.size
                    draw(chevron, in: NSRect(x: bounds.width - LiveStateMenuMetrics.trailingPadding - size.width, y: top + (row.height - size.height) / 2,
                                             width: size.width, height: size.height), color: textColor)
                }
            }
        }
    }

    static func fitted(_ size: CGSize, maximum: CGFloat) -> CGSize {
        guard size.width > maximum || size.height > maximum, size.width > 0, size.height > 0 else { return size }
        let scale = min(maximum / size.width, maximum / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }

    private func draw(_ image: NSImage, in rect: NSRect, color: NSColor) {
        guard image.isTemplate else {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            return
        }
        let resolved = color.usingColorSpace(.sRGB) ?? color
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            image.draw(in: bounds)
            resolved.set()
            bounds.fill(using: .sourceAtop)
            return true
        }
        tinted.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }
}

@MainActor
final class LiveStateMenuPanel {
    let menu: NSMenu
    let container: LiveStateMenuContainerView
    let rowsView: LiveStateMenuRowsView
    let frameInWindow: NSRect
    let parentRow: Int?

    init(menu: NSMenu, layout: LiveStateMenuLayout, frameInWindow: NSRect, parentRow: Int?, window: NSWindow, frameView: NSView, above sibling: NSView?) {
        self.menu = menu
        self.frameInWindow = frameInWindow
        self.parentRow = parentRow
        container = LiveStateMenuContainerView(frame: frameView.convert(frameInWindow, from: nil))
        let isDark = window.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        container.wantsLayer = true
        container.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(isDark ? 0.55 : 0.22)
            shadow.shadowBlurRadius = 24
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            return shadow
        }()
        let material = NSVisualEffectView(frame: container.bounds)
        material.material = .menu
        material.blendingMode = .withinWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = LiveStateMenuMetrics.cornerRadius
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = (isDark ? NSColor.white.withAlphaComponent(0.2) : NSColor.black.withAlphaComponent(0.16)).cgColor
        material.autoresizingMask = [.width, .height]
        container.addSubview(material)
        let tint = NSView(frame: material.bounds)
        tint.wantsLayer = true
        tint.layer?.backgroundColor = (isDark ? NSColor(white: 0.235, alpha: 0.97) : NSColor(white: 0.995, alpha: 0.97)).cgColor
        tint.autoresizingMask = [.width, .height]
        material.addSubview(tint)
        rowsView = LiveStateMenuRowsView(menu: menu, layout: layout, frame: container.bounds)
        rowsView.autoresizingMask = [.width, .height]
        container.addSubview(rowsView)
        container.appearance = window.effectiveAppearance
        frameView.addSubview(container, positioned: .above, relativeTo: sibling)
    }

    var isComposited: Bool { container.layer?.superlayer != nil }

    func move(into view: NSView, above sibling: NSView) {
        container.removeFromSuperview()
        container.frame = view.convert(frameInWindow, from: nil)
        view.addSubview(container, positioned: .above, relativeTo: sibling)
    }

    func row(atWindowPoint point: NSPoint) -> Int? {
        guard frameInWindow.contains(point) else { return nil }
        return rowsView.layout.rowIndex(atY: frameInWindow.maxY - point.y + rowsView.scrollOffset)
    }

    func rowTopInWindow(_ row: Int) -> CGFloat {
        frameInWindow.maxY - (rowsView.layout.rows[row].top - rowsView.scrollOffset)
    }

    func scrollToShow(_ row: Int) {
        let layoutRow = rowsView.layout.rows[row]
        let visibleHeight = frameInWindow.height
        if layoutRow.top - rowsView.scrollOffset < 0 { rowsView.scrollOffset = layoutRow.top - LiveStateMenuMetrics.verticalPadding }
        if layoutRow.bottom - rowsView.scrollOffset > visibleHeight { rowsView.scrollOffset = layoutRow.bottom - visibleHeight + LiveStateMenuMetrics.verticalPadding }
        rowsView.scrollOffset = max(0, min(rowsView.scrollOffset, rowsView.layout.size.height - visibleHeight))
    }

    func remove() {
        container.removeFromSuperview()
    }
}

@MainActor
final class LiveStateMenuPresenter {
    static let shared = LiveStateMenuPresenter()

    private(set) var panels: [LiveStateMenuPanel] = []
    private weak var window: NSWindow?
    private var popUpCell: NSPopUpButtonCell?
    private var source = ""
    var isPointerDown = false
    var pointerDownScreenPoint: NSPoint?
    var menuWindowProvider: () -> NSWindow? = { nil }
    private var gestureOpenedMenu = false
    private var pointerMovedSinceDown = false
    private var gestureInMenu = false
    private var retainedTargets: [AnyObject] = []

    var isShowing: Bool { !panels.isEmpty }
    var hostWindow: NSWindow? { window }

    func present(_ menu: NSMenu, in window: NSWindow, anchor: LiveStateMenuAnchor, minimumWidth: CGFloat, source: String) -> Bool {
        guard let contentView = window.contentView else {
            LiveStateLog.event("menu_presentation_unavailable", ["source": source, "reason": "The window has no content view."])
            return false
        }
        if isShowing { close(reason: "replaced") }
        if case .popUpButton(let cell, _) = anchor {
            if let control = cell.controlView { NotificationCenter.default.post(name: NSPopUpButton.willPopUpNotification, object: control) }
            NotificationCenter.default.post(name: NSPopUpButtonCell.willPopUpNotification, object: cell)
            let willShowMenu = NSSelectorFromString("popUpButtonCell:willShowMenu:")
            if let delegate = menu.delegate as? NSObject, delegate.responds(to: willShowMenu) {
                _ = delegate.perform(willShowMenu, with: cell, with: menu)
            }
        }
        Self.prepare(menu)
        var minimumWidth = minimumWidth
        var popUpCell: NSPopUpButtonCell?
        if case .popUpButton(let cell, let rect) = anchor {
            popUpCell = cell
            minimumWidth = max(minimumWidth, cell.pullsDown ? rect.width : rect.width + LiveStateMenuMetrics.titleX - LiveStateMenuMetrics.popUpTitleInset)
        }
        let layout = LiveStateMenuLayout(menu: menu, minimumWidth: minimumWidth, skipsFirstItem: popUpCell?.pullsDown == true)
        guard !layout.rows.isEmpty else {
            var fields: [String: Any] = ["source": source, "reason": "The menu has no visible items.", "menuItems": menu.numberOfItems, "anchor": anchor.name]
            if case .popUpButton(let cell, _) = anchor {
                fields["cellClass"] = String(describing: type(of: cell))
                fields["controlClass"] = cell.controlView.map { String(describing: type(of: $0)) } ?? NSNull()
                fields["controlMenuItems"] = (cell.controlView as? NSPopUpButton)?.menu?.numberOfItems ?? NSNull()
                fields["cellMenuIsSame"] = cell.menu === menu
                fields["menuDelegateClass"] = menu.delegate.map { String(describing: type(of: $0)) } ?? NSNull()
            }
            LiveStateLog.event("menu_presentation_unavailable", fields)
            return false
        }
        var frame = CGRect(origin: .zero, size: layout.size)
        var highlighted: Int?
        switch anchor {
        case .item(let item, let topLeft):
            let rowIndex = item.flatMap { item in layout.rows.firstIndex { $0.item === item } }
            frame.origin.x = topLeft.x
            frame.origin.y = topLeft.y + (rowIndex.map { layout.rows[$0].top } ?? 0) - frame.height
            highlighted = rowIndex
        case .below(let rect):
            frame.origin.x = rect.minX
            frame.origin.y = rect.minY - 2 - frame.height
        case .popUpButton(let cell, let rect):
            if cell.pullsDown {
                frame.origin.x = rect.minX
                frame.origin.y = rect.minY - 2 - frame.height
            } else {
                let rowIndex = cell.selectedItem.flatMap { item in layout.rows.firstIndex { $0.item === item } } ?? 0
                let row = layout.rows[rowIndex]
                frame.origin.x = rect.minX + LiveStateMenuMetrics.popUpTitleInset - layout.titleX
                frame.origin.y = rect.midY + row.top + row.height / 2 - frame.height
                highlighted = rowIndex
            }
        }
        var hostWindow = window
        var hostContentView = contentView
        var hostFrame = frame
        var placement = "content_view"
        if let menuWindow = menuWindowProvider(), menuWindow !== window, let menuContentView = menuWindow.contentView {
            hostFrame = menuWindow.convertFromScreen(window.convertToScreen(frame))
            hostWindow = menuWindow
            hostContentView = menuContentView
            placement = "menu_window"
        }
        let placed = Self.clamp(hostFrame, in: hostContentView.convert(hostContentView.bounds, to: nil))
        let panel = LiveStateMenuPanel(menu: menu, layout: layout, frameInWindow: placed, parentRow: nil, window: hostWindow, frameView: hostContentView, above: nil)
        hostContentView.layoutSubtreeIfNeeded()
        hostWindow.displayIfNeeded()
        if !panel.isComposited, let frameView = hostContentView.superview {
            panel.move(into: frameView, above: hostContentView)
            placement = "frame_view_above_content_view"
        }
        if let highlighted, layout.rows[highlighted].isSelectable {
            panel.rowsView.highlightedRow = highlighted
            panel.scrollToShow(highlighted)
        }
        panels = [panel]
        self.window = hostWindow
        retainedTargets = Self.targets(of: menu)
        self.popUpCell = popUpCell
        self.source = source
        gestureOpenedMenu = isPointerDown
        pointerMovedSinceDown = false
        gestureInMenu = isPointerDown
        hostWindow.displayIfNeeded()
        LiveStateLog.event("menu_presented", [
            "source": source, "anchor": anchor.name, "menu": menu.title, "items": layout.rows.count, "windowNumber": hostWindow.windowNumber,
            "openingWindowNumber": window.windowNumber,
            "frame": NSStringFromRect(placed), "openedDuringPointerGesture": gestureOpenedMenu,
            "contentViewClass": String(describing: type(of: contentView)), "placement": placement,
        ])
        return true
    }

    func close(reason: String) {
        guard isShowing else { return }
        let closed = panels
        panels = []
        for panel in closed.reversed() {
            panel.remove()
            panel.menu.delegate?.menuDidClose?(panel.menu)
        }
        window?.displayIfNeeded()
        LiveStateLog.event("menu_closed", ["source": source, "reason": reason, "panels": closed.count])
        window = nil
        popUpCell = nil
        gestureInMenu = false
        retainedTargets = []
    }

    func pointerDown(at screenPoint: NSPoint) -> LiveStateMenuPointerOutcome {
        guard let point = windowPoint(screenPoint), panelIndex(at: point) != nil else {
            close(reason: "outside_click")
            return .closedOutside
        }
        gestureInMenu = true
        pointerMovedSinceDown = false
        pointerDownScreenPoint = screenPoint
        return pointerMoved(to: screenPoint, dragging: false)
    }

    @discardableResult
    func pointerMoved(to screenPoint: NSPoint, dragging: Bool) -> LiveStateMenuPointerOutcome {
        if dragging, pointerDownScreenPoint.map({ hypot(screenPoint.x - $0.x, screenPoint.y - $0.y) > 3 }) ?? true { pointerMovedSinceDown = true }
        guard let point = windowPoint(screenPoint), let panelIndex = panelIndex(at: point) else {
            panels.last?.rowsView.highlightedRow = nil
            return .insideMenu
        }
        let panel = panels[panelIndex]
        guard let row = panel.row(atWindowPoint: point) else {
            panel.rowsView.highlightedRow = nil
            return .insideMenu
        }
        let layoutRow = panel.rowsView.layout.rows[row]
        if panelIndex + 1 < panels.count, panels[panelIndex + 1].parentRow != row { closeSubmenus(above: panelIndex) }
        panel.rowsView.highlightedRow = layoutRow.isSelectable ? row : nil
        if layoutRow.isSelectable, layoutRow.item.hasSubmenu, panels.count == panelIndex + 1 {
            openSubmenu(of: panelIndex, row: row)
            return .openedSubmenu
        }
        return layoutRow.isSelectable ? .highlighted : .insideMenu
    }

    func pointerUp(at screenPoint: NSPoint) -> LiveStateMenuPointerOutcome {
        defer {
            gestureInMenu = false
            gestureOpenedMenu = false
        }
        guard gestureInMenu, pointerMovedSinceDown || !gestureOpenedMenu else { return .insideMenu }
        guard let point = windowPoint(screenPoint), let panelIndex = panelIndex(at: point) else { return .insideMenu }
        return activate(panelIndex: panelIndex, point: point)
    }

    func click(at screenPoint: NSPoint) -> LiveStateMenuPointerOutcome {
        guard let point = windowPoint(screenPoint), let panelIndex = panelIndex(at: point) else {
            close(reason: "outside_click")
            return .closedOutside
        }
        pointerMoved(to: screenPoint, dragging: false)
        return activate(panelIndex: panelIndex, point: point)
    }

    func scroll(at screenPoint: NSPoint, deltaY: Double) {
        guard let point = windowPoint(screenPoint), let panelIndex = panelIndex(at: point) else { return }
        let panel = panels[panelIndex]
        let maximum = max(0, panel.rowsView.layout.size.height - panel.frameInWindow.height)
        panel.rowsView.scrollOffset = max(0, min(maximum, panel.rowsView.scrollOffset - CGFloat(deltaY)))
    }

    func key(_ name: String) -> String {
        guard let panel = panels.last else { return "none" }
        let rows = panel.rowsView.layout.rows
        switch name {
        case "escape":
            close(reason: "escape")
            return "closed"
        case "up", "down":
            let selectable = rows.indices.filter { rows[$0].isSelectable }
            guard !selectable.isEmpty else { return "none" }
            let next: Int
            if let current = panel.rowsView.highlightedRow, let position = selectable.firstIndex(of: current) {
                next = selectable[name == "down" ? min(position + 1, selectable.count - 1) : max(position - 1, 0)]
            } else {
                next = name == "down" ? selectable[0] : selectable[selectable.count - 1]
            }
            panel.rowsView.highlightedRow = next
            panel.scrollToShow(next)
            return "highlighted"
        case "right":
            if panels.count > 1, panel.rowsView.highlightedRow == nil {
                highlightFirst(in: panel)
                return "highlighted"
            }
            guard let row = panel.rowsView.highlightedRow, rows[row].item.hasSubmenu else { return "none" }
            openSubmenu(of: panels.count - 1, row: row)
            highlightFirst(in: panels[panels.count - 1])
            return "opened_submenu"
        case "left":
            guard panels.count > 1 else { return "none" }
            closeSubmenus(above: panels.count - 2)
            return "closed_submenu"
        case "return", "space":
            guard let row = panel.rowsView.highlightedRow, rows[row].isSelectable else { return "none" }
            if rows[row].item.hasSubmenu {
                if panels.last?.parentRow != row || panels.count == 1 { openSubmenu(of: panels.count - 1, row: row) }
                highlightFirst(in: panels[panels.count - 1])
                return "opened_submenu"
            }
            choose(rows[row].item)
            return "chose"
        default:
            return "none"
        }
    }

    func typeSelect(_ text: String) -> String {
        guard let panel = panels.last else { return "none" }
        let rows = panel.rowsView.layout.rows
        guard let row = rows.indices.first(where: { rows[$0].isSelectable && rows[$0].item.title.lowercased().hasPrefix(text.lowercased()) }) else { return "none" }
        panel.rowsView.highlightedRow = row
        panel.scrollToShow(row)
        return "highlighted"
    }

    private func activate(panelIndex: Int, point: NSPoint) -> LiveStateMenuPointerOutcome {
        let panel = panels[panelIndex]
        guard let row = panel.row(atWindowPoint: point) else { return .insideMenu }
        let layoutRow = panel.rowsView.layout.rows[row]
        guard layoutRow.isSelectable else { return .insideMenu }
        if layoutRow.item.hasSubmenu {
            if panels.count == panelIndex + 1 { openSubmenu(of: panelIndex, row: row) }
            return .openedSubmenu
        }
        choose(layoutRow.item)
        return .chose
    }

    private func choose(_ item: NSMenuItem) {
        guard let menu = item.menu else { return close(reason: "chosen_item_has_no_menu") }
        let index = menu.index(of: item)
        let cell = popUpCell
        let targets = retainedTargets
        let selectionBefore = cell?.indexOfSelectedItem
        let fields: [String: Any] = [
            "source": source, "title": item.title, "index": index, "menu": menu.title,
            "target": item.target.map { String(describing: type(of: $0)) } ?? NSNull(), "action": item.action.map(NSStringFromSelector) ?? NSNull(),
        ]
        close(reason: "chosen")
        guard index >= 0 else { return }
        menu.performActionForItem(at: index)
        var logged = fields
        if let cell, cell.menu === menu, !cell.pullsDown, cell.indexOfSelectedItem != index {
            cell.selectItem(at: index)
            if let control = cell.controlView as? NSControl { control.sendAction(cell.action, to: cell.target) }
            logged["popUpSelectionSetByPackage"] = true
        }
        logged["selectedIndexBefore"] = selectionBefore ?? NSNull()
        logged["selectedIndexAfter"] = cell?.indexOfSelectedItem ?? NSNull()
        LiveStateLog.event("menu_item_chosen", logged)
        withExtendedLifetime(targets) {}
    }

    private func openSubmenu(of panelIndex: Int, row: Int) {
        closeSubmenus(above: panelIndex)
        let parent = panels[panelIndex]
        guard let submenu = parent.rowsView.layout.rows[row].item.submenu, let window, let frameView = parent.container.superview, let contentView = window.contentView else { return }
        Self.prepare(submenu)
        retainedTargets += Self.targets(of: submenu)
        let layout = LiveStateMenuLayout(menu: submenu, minimumWidth: 0)
        guard !layout.rows.isEmpty else { return }
        let bounds = contentView.convert(contentView.bounds, to: nil)
        var frame = CGRect(origin: .zero, size: layout.size)
        frame.origin.x = parent.frameInWindow.maxX - LiveStateMenuMetrics.submenuOverlap
        if frame.maxX > bounds.maxX - LiveStateMenuMetrics.windowMargin { frame.origin.x = parent.frameInWindow.minX - frame.width + LiveStateMenuMetrics.submenuOverlap }
        frame.origin.y = parent.rowTopInWindow(row) + LiveStateMenuMetrics.verticalPadding - frame.height
        let placed = Self.clamp(frame, in: bounds)
        panels.append(LiveStateMenuPanel(menu: submenu, layout: layout, frameInWindow: placed, parentRow: row, window: window, frameView: frameView, above: panels.last?.container))
        window.displayIfNeeded()
        LiveStateLog.event("menu_submenu_opened", ["source": source, "title": parent.rowsView.layout.rows[row].item.title, "items": layout.rows.count, "frame": NSStringFromRect(placed)])
    }

    private func closeSubmenus(above panelIndex: Int) {
        while panels.count > panelIndex + 1 {
            let panel = panels.removeLast()
            panel.remove()
            panel.menu.delegate?.menuDidClose?(panel.menu)
        }
    }

    private func highlightFirst(in panel: LiveStateMenuPanel) {
        guard let first = panel.rowsView.layout.rows.indices.first(where: { panel.rowsView.layout.rows[$0].isSelectable }) else { return }
        panel.rowsView.highlightedRow = first
    }

    private func windowPoint(_ screenPoint: NSPoint) -> NSPoint? {
        window?.convertPoint(fromScreen: screenPoint)
    }

    private func panelIndex(at point: NSPoint) -> Int? {
        panels.indices.last { panels[$0].frameInWindow.contains(point) }
    }

    private static func targets(of menu: NSMenu) -> [AnyObject] {
        menu.items.flatMap { item in (item.target.map { [$0] } ?? []) + (item.submenu.map { targets(of: $0) } ?? []) }
    }

    private static func prepare(_ menu: NSMenu) {
        menu.delegate?.menuNeedsUpdate?(menu)
        if let delegate = menu.delegate, let count = delegate.numberOfItems?(in: menu), count >= 0 {
            while menu.numberOfItems < count { menu.addItem(NSMenuItem()) }
            while menu.numberOfItems > count { menu.removeItem(at: menu.numberOfItems - 1) }
            for index in 0..<count where !(delegate.menu?(menu, update: menu.items[index], at: index, shouldCancel: false) ?? true) { break }
        }
        menu.update()
        menu.delegate?.menuWillOpen?(menu)
    }

    private static func clamp(_ frame: CGRect, in bounds: CGRect) -> CGRect {
        let margin = LiveStateMenuMetrics.windowMargin
        var result = frame
        result.size.height = min(result.height, bounds.height - margin * 2)
        result.size.width = min(result.width, bounds.width - margin * 2)
        result.origin.x = min(max(result.minX, bounds.minX + margin), bounds.maxX - margin - result.width)
        result.origin.y = min(max(result.minY, bounds.minY + margin), bounds.maxY - margin - result.height)
        return result.integral
    }
}

final class LiveStateMenuWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @MainActor
    convenience init(around windows: [NSWindow], margin: NSEdgeInsets) {
        let union = windows.dropFirst().reduce(windows.first?.frame ?? .zero) { $0.union($1.frame) }
        let frame = CGRect(x: union.minX - margin.left, y: union.minY - margin.bottom,
                           width: union.width + margin.left + margin.right, height: union.height + margin.top + margin.bottom).integral
        self.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        contentView = NSView(frame: CGRect(origin: .zero, size: frame.size))
        LiveStateLog.event("menu_window_created", ["frame": NSStringFromRect(frame), "margin": [margin.top, margin.left, margin.bottom, margin.right]])
    }
}
