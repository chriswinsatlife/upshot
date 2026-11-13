import AppKit
import SwiftUI

extension Color {
    static let ink = Color(nsColor: NSColor(name: "upshot.ink") { $0.isDarkAppearance ? .white : .black })
    static let inkInverse = Color(nsColor: NSColor(name: "upshot.inkInverse") { $0.isDarkAppearance ? .black : .white })

    static func appearanceDependent(_ name: String, light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: NSColor.Name(name)) { $0.isDarkAppearance ? dark : light })
    }
}

extension NSAppearance {
    var isDarkAppearance: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

enum Palette {
    static let accent = Color.accentColor
    static let onAccent = Color.white
    static let highlight = Color.accentColor
    static let layoutCue = Color(nsColor: .systemGreen)
    static let textCue = Color(nsColor: .systemPurple)
    static let record = Color(nsColor: .systemRed)
    static let destructive = Color(nsColor: .systemRed)
    static let destructiveLabel = Color.appearanceDependent(
        "upshot.destructiveLabel",
        light: NSColor(srgbRed: 0xC7 / 255.0, green: 0x21 / 255.0, blue: 0x1C / 255.0, alpha: 1),
        dark: NSColor(srgbRed: 0xFF / 255.0, green: 0x69 / 255.0, blue: 0x61 / 255.0, alpha: 1)
    )
    static let success = Color(nsColor: .systemGreen)
    static let warning = Color(nsColor: .systemOrange)

    static let label = Color.ink.opacity(0.88)
    static let secondaryLabel = Color.ink.opacity(0.55)
    static let tertiaryLabel = Color.ink.opacity(0.32)
    static let disabledLabel = Color.ink.opacity(0.28)

    static let fill = Color.primary.opacity(0.055)
    static let hoverFill = Color.primary.opacity(0.07)
    static let pressedFill = Color.primary.opacity(0.12)
    static let selectedFill = Color.primary.opacity(0.10)
    static let hairline = Color.primary.opacity(0.10)
    static let strongHairline = Color.primary.opacity(0.18)

    static let controlFill = Color.appearanceDependent(
        "upshot.controlFill",
        light: NSColor(white: 0, alpha: 0.065),
        dark: NSColor(white: 1, alpha: 0.10)
    )
    static let controlHoverFill = Color.appearanceDependent(
        "upshot.controlHoverFill",
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.15)
    )
    static let controlPressedFill = Color.appearanceDependent(
        "upshot.controlPressedFill",
        light: NSColor(white: 0, alpha: 0.15),
        dark: NSColor(white: 1, alpha: 0.21)
    )
    static let destructiveFill = Color.appearanceDependent(
        "upshot.destructiveFill",
        light: NSColor.systemRed.withAlphaComponent(0.10),
        dark: NSColor.systemRed.withAlphaComponent(0.18)
    )
    static let destructiveHoverFill = Color.appearanceDependent(
        "upshot.destructiveHoverFill",
        light: NSColor.systemRed.withAlphaComponent(0.16),
        dark: NSColor.systemRed.withAlphaComponent(0.26)
    )
    static let destructivePressedFill = Color.appearanceDependent(
        "upshot.destructivePressedFill",
        light: NSColor.systemRed.withAlphaComponent(0.22),
        dark: NSColor.systemRed.withAlphaComponent(0.34)
    )

    static let fieldFill = Color.appearanceDependent(
        "upshot.fieldFill",
        light: NSColor(white: 1, alpha: 1),
        dark: NSColor(white: 1, alpha: 0.06)
    )
    static let fieldStroke = Color.appearanceDependent(
        "upshot.fieldStroke",
        light: NSColor(white: 0, alpha: 0.13),
        dark: NSColor(white: 1, alpha: 0.10)
    )

    static let sidebarSelectionFill = Color.appearanceDependent(
        "upshot.sidebarSelectionFill",
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.14)
    )
    static let sidebarHoverFill = Color.appearanceDependent(
        "upshot.sidebarHoverFill",
        light: NSColor(white: 0, alpha: 0.035),
        dark: NSColor(white: 1, alpha: 0.04)
    )
    static let sidebarPressedFill = Color.appearanceDependent(
        "upshot.sidebarPressedFill",
        light: NSColor(white: 0, alpha: 0.16),
        dark: NSColor(white: 1, alpha: 0.20)
    )

    static let floatingSelectionFill = Color.appearanceDependent(
        "upshot.floatingSelectionFill",
        light: NSColor(white: 0, alpha: 0.14),
        dark: NSColor(white: 1, alpha: 0.20)
    )
    static let floatingHoverFill = Color.appearanceDependent(
        "upshot.floatingHoverFill",
        light: NSColor(white: 0, alpha: 0.05),
        dark: NSColor(white: 1, alpha: 0.07)
    )
    static let floatingPressedFill = Color.appearanceDependent(
        "upshot.floatingPressedFill",
        light: NSColor(white: 0, alpha: 0.20),
        dark: NSColor(white: 1, alpha: 0.28)
    )
    static let floatingStroke = Color.appearanceDependent(
        "upshot.floatingStroke",
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.12)
    )
    static let floatingPanelBase = Color.appearanceDependent(
        "upshot.floatingPanelBase",
        light: NSColor(white: 1, alpha: 0.45),
        dark: NSColor(white: 0.10, alpha: 0.72)
    )
    static let modeSwitchSelectionFill = Color.appearanceDependent(
        "upshot.modeSwitchSelectionFill",
        light: NSColor(white: 1, alpha: 1),
        dark: NSColor(white: 1, alpha: 0.18)
    )
    static let floatingDivider = Color.appearanceDependent(
        "upshot.floatingDivider",
        light: NSColor(white: 0, alpha: 0.10),
        dark: NSColor(white: 1, alpha: 0.10)
    )

    static let panel = Color.appearanceDependent(
        "upshot.panel",
        light: .white,
        dark: .windowBackgroundColor
    )
    static let workspace = Color.appearanceDependent(
        "upshot.workspace",
        light: NSColor(white: 0.93, alpha: 1),
        dark: NSColor(white: 0.16, alpha: 1)
    )
}

enum Radius {
    static let tile: CGFloat = 6
    static let control: CGFloat = 6
    static let field: CGFloat = 8
    static let sidebarIconTile: CGFloat = 5
    static let sidebarRow: CGFloat = 8
    static let thumbnail: CGFloat = 10
    static let toolbarButton: CGFloat = 10
    static let flyout: CGFloat = 14
    static let panel: CGFloat = 16
    static let card: CGFloat = 16
    static let hud: CGFloat = 22
    static let pill: CGFloat = 1000

    static func nested(inner: CGFloat, padding: CGFloat) -> CGFloat { inner + padding }
}

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 6
    static let m: CGFloat = 8
    static let ml: CGFloat = 10
    static let l: CGFloat = 12
    static let xl: CGFloat = 16
    static let xxl: CGFloat = 20
    static let xxxl: CGFloat = 28
}

enum InterfaceMetrics {
    static let sidebarWidth: CGFloat = 200
    static let sidebarRowHeight: CGFloat = 28
    static let sidebarRowHorizontalPadding: CGFloat = 8
    static let sidebarIconTileSize: CGFloat = 18
    static let sidebarIconGlyphPointSize: CGFloat = 10
    static let sidebarIconToLabelSpacing: CGFloat = 2.5
    static let sidebarGroupSpacing: CGFloat = 14
    static let searchFieldHeight: CGFloat = 28

    static let controlHeight: CGFloat = 22
    static let actionButtonHorizontalPadding: CGFloat = 10
    static let actionButtonIconToLabelSpacing: CGFloat = 5
    static let fieldHorizontalPadding: CGFloat = 8
    static let shortcutFieldWidth: CGFloat = 120
    static let shortcutFieldClearButtonWidth: CGFloat = 20
    static let resetButtonSize: CGFloat = 20
    static let flyoutPadding: CGFloat = 5
    static let rowMinimumHeight: CGFloat = 26
    static let rowLabelToDetailSpacing: CGFloat = 2
    static let rowControlSpacing: CGFloat = 8

    static let floatingPanelPadding: CGFloat = 6
    static let floatingDividerInset: CGFloat = 10
    static let toolbarButtonMinimumWidth: CGFloat = 62
    static let toolbarButtonHeight: CGFloat = 52
    static let toolbarIconPointSize: CGFloat = 17
    static let toolbarIconToLabelSpacing: CGFloat = 5
    static let modeSwitchHeight: CGFloat = 28
    static let sizeFieldWidth: CGFloat = 56
    static let sizeFieldHeight: CGFloat = 30
    static let flyoutRowHeight: CGFloat = 36
    static let flyoutMinimumWidth: CGFloat = 248
    static let flyoutIconSlotWidth: CGFloat = 20
    static let toastMinimumHeight: CGFloat = 40
    static let cardPadding: CGFloat = 12
}

extension Font {
    static let dsDisplay = Font.system(size: 22, weight: .bold)
    static let dsTitle = Font.system(size: 15, weight: .semibold)
    static let dsHeadline = Font.system(size: 13, weight: .semibold)
    static let dsBody = Font.system(size: 13)
    static let dsBodyEmphasis = Font.system(size: 13, weight: .medium)
    static let dsControl = Font.system(size: 12, weight: .semibold)
    static let dsCallout = Font.system(size: 12)
    static let dsCaption = Font.system(size: 11)
    static let dsToolbarLabel = Font.system(size: 11, weight: .medium)
    static let dsSegment = Font.system(size: 12, weight: .medium)
    static let dsSegmentSelected = Font.system(size: 12, weight: .semibold)
    static let dsGroupLabel = Font.system(size: 11, weight: .semibold)
    static let dsKeyHint = Font.system(size: 12)
    static let dsMicro = Font.system(size: 10, weight: .semibold)
    static let dsNumeric = Font.system(size: 12, weight: .medium).monospacedDigit()
    static let dsFieldNumeric = Font.system(size: 13).monospacedDigit()
    static let dsSizeField = Font.system(size: 14, weight: .medium).monospacedDigit()
}

extension View {
    func surface(selected: Bool = false, radius: CGFloat = Radius.card) -> some View {
        background(
            selected ? Palette.selectedFill : Palette.fill,
            in: RoundedRectangle(cornerRadius: radius, style: .continuous)
        )
    }

    func hairline(radius: CGFloat, opacity: Double = 0.10) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.primary.opacity(opacity), lineWidth: 0.5)
                .allowsHitTesting(false)
        }
    }
}

enum IconSize {
    static let actionButton: CGFloat = 11.5
    static let row: CGFloat = 13
    static let searchField: CGFloat = 12
    static let segment: CGFloat = 11
    static let flyout: CGFloat = 14
    static let toast: CGFloat = 15
    static let sizeMenu: CGFloat = 15
    static let toolbar: CGFloat = 17
    static let disclosureChevron: CGFloat = 9
}
