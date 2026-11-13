import AppKit
import SwiftUI

struct InterfaceStyleGallery: View {
    let backdrop: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxxl) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text("Interface Styles")
                    .font(.dsDisplay)
                    .foregroundStyle(Palette.label)
                Text("Every shared component in every state. Screens use these components and never define their own button, row, or panel style.")
                    .font(.dsCallout)
                    .foregroundStyle(Palette.secondaryLabel)
            }

            InterfaceStyleGalleryWindowRegion()

            InterfaceStyleGalleryFloatingRegion(backdrop: backdrop)
        }
        .padding(Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.interfacePresentedControlState, .normal)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

private struct InterfaceStyleGalleryRegionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.dsTitle)
            .foregroundStyle(Palette.label)
    }
}

private struct InterfaceStyleGalleryComponentTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.dsGroupLabel)
            .foregroundStyle(Palette.secondaryLabel)
            .textCase(.uppercase)
    }
}

private struct InterfaceStyleGallerySample<Content: View>: View {
    let state: String
    var onBackdrop = false
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .center, spacing: Space.s) {
            content()
            Text(state)
                .font(.dsCaption)
                .foregroundStyle(Palette.secondaryLabel)
                .padding(.horizontal, onBackdrop ? Space.s : 0)
                .padding(.vertical, onBackdrop ? Space.xxs : 0)
                .background {
                    if onBackdrop {
                        Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                    }
                }
        }
    }
}

private struct InterfaceStyleGalleryWindowRegion: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            InterfaceStyleGalleryRegionTitle(title: "Windows")
            HStack(alignment: .top, spacing: Space.xxl) {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    InterfaceStyleGallerySidebarColumn()
                    InterfaceStyleGalleryActionButtonGrid()
                    InterfaceStyleGalleryWindowModeSwitch()
                }
                .frame(width: 520, alignment: .leading)

                InterfaceStyleGalleryFormColumn()
                    .frame(width: 720, height: 1760)
            }
        }
    }
}

private struct InterfaceStyleGallerySidebarColumn: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InterfaceStyleGalleryComponentTitle(title: "Sidebar")
            HStack(alignment: .top, spacing: Space.l) {
                InterfaceSidebar(searchPrompt: "Search Settings", searchText: .constant("")) {
                    InterfaceSidebarRow("General", systemImage: "gearshape", tint: InterfaceSidebarTint.gray, isSelected: true) {}
                    InterfaceSidebarRow("Screenshots", systemImage: "camera", tint: InterfaceSidebarTint.blue, isSelected: false) {}
                        .interfacePresentedControlState(.hover)
                    InterfaceSidebarRow("Screen Recordings", systemImage: "video", tint: InterfaceSidebarTint.red, isSelected: false) {}
                        .interfacePresentedControlState(.pressed)
                    InterfaceSidebarRow("Overlay", systemImage: "square.stack", tint: InterfaceSidebarTint.teal, isSelected: false) {}
                    InterfaceSidebarRow("MCP", systemImage: "point.3.filled.connected.trianglepath.dotted", tint: InterfaceSidebarTint.purple, isSelected: false) {}
                        .interfacePresentedControlState(.disabled)
                    InterfaceSidebarRow("Cloud", systemImage: "icloud", tint: InterfaceSidebarTint.blue, isSelected: false) {}
                    InterfaceSidebarGroupHeader("Library")
                    InterfaceSidebarRow("All Captures", systemImage: "square.stack.3d.up", tint: InterfaceSidebarTint.indigo, count: 15, isSelected: false) {}
                    InterfaceSidebarRow("Screenshots", systemImage: "photo", tint: InterfaceSidebarTint.blue, count: 12, isSelected: false) {}
                    InterfaceSidebarRow("Recordings", systemImage: "video", tint: InterfaceSidebarTint.red, count: 3, isSelected: false) {}
                    InterfaceSidebarGroupHeader("Apps")
                    InterfaceSidebarRow("Upshot", icon: .image(NSImage(named: NSImage.applicationIconName) ?? NSImage()), count: 4, isSelected: false) {}
                }
                .padding(.vertical, Space.ml)
                .frame(width: InterfaceMetrics.sidebarWidth, height: 430)
                .background(Palette.workspace, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: Space.s) {
                    InterfaceStyleGalleryStateList(states: [
                        ("General", "Selected"),
                        ("Screenshots", "Hover"),
                        ("Screen Recordings", "Pressed"),
                        ("Overlay", "Normal"),
                        ("MCP", "Disabled")
                    ])
                    VStack(alignment: .leading, spacing: Space.s) {
                        InterfaceStyleGallerySample(state: "Search, focused") {
                            InterfaceSidebarSearchField(prompt: "Search Settings", text: .constant("shortcut"))
                                .interfacePresentedControlState(.selected)
                                .frame(width: 180)
                        }
                    }
                    .padding(.top, Space.m)
                }
            }
        }
    }
}

private struct InterfaceStyleGalleryStateList: View {
    let states: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ForEach(states, id: \.0) { row, state in
                Text("\(Text(row).foregroundStyle(Palette.label)): \(Text(state).foregroundStyle(Palette.secondaryLabel))")
                    .font(.dsCaption)
            }
        }
        .padding(.top, InterfaceMetrics.searchFieldHeight + Space.m + Space.ml)
    }
}

private struct InterfaceStyleGalleryActionButtonGrid: View {
    private let states: [InterfacePresentedControlState] = [.normal, .hover, .pressed, .disabled]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InterfaceStyleGalleryComponentTitle(title: "Action Button")
            Grid(alignment: .leading, horizontalSpacing: Space.l, verticalSpacing: Space.l) {
                GridRow {
                    Text("")
                    ForEach(states) { state in
                        Text(state.title)
                            .font(.dsCaption)
                            .foregroundStyle(Palette.secondaryLabel)
                    }
                }
                GridRow {
                    Text("Action").font(.dsCaption).foregroundStyle(Palette.secondaryLabel)
                    ForEach(states) { state in
                        Button("Choose…") {}
                            .buttonStyle(.interfaceAction)
                            .interfacePresentedControlState(state)
                    }
                }
                GridRow {
                    Text("With icon").font(.dsCaption).foregroundStyle(Palette.secondaryLabel)
                    ForEach(states) { state in
                        InterfaceActionButton("Reveal", systemImage: "folder") {}
                            .interfacePresentedControlState(state)
                    }
                }
                GridRow {
                    Text("Destructive").font(.dsCaption).foregroundStyle(Palette.secondaryLabel)
                    ForEach(states) { state in
                        InterfaceActionButton("Delete", role: .destructive) {}
                            .interfacePresentedControlState(state)
                    }
                }
            }
        }
    }
}

private struct InterfaceStyleGalleryFormColumn: View {
    private let folderURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures", isDirectory: true)

    var body: some View {
        InterfaceFormPage {
            InterfaceSection("Section Header", footer: "Section footer text explains a whole section in one sentence when the rows cannot.") {
                InterfaceRow("Row") {
                    InterfaceValueWithUnitLabel(value: "80", unit: "%", unitSpacing: .none)
                }
                InterfaceRow("Row with detail", detail: "Detail text appears only when the title is not enough.") {
                    InterfaceValueWithUnitLabel(value: "3", unit: "seconds")
                }
                InterfaceRow("Row with icon", systemImage: "mic.fill") {
                    InterfaceActionButton("Allow") {}
                }
            }

            InterfaceSection("Toggle Row") {
                InterfaceToggleRow("On", isOn: .constant(true))
                InterfaceToggleRow("Off", isOn: .constant(false))
                InterfaceToggleRow("Disabled, on", isOn: .constant(true))
                    .interfacePresentedControlState(.disabled)
                InterfaceToggleRow("Disabled, off", isOn: .constant(false))
                    .interfacePresentedControlState(.disabled)
            }

            InterfaceSection("Picker Row") {
                InterfacePickerRow("Normal", selection: .constant(5)) {
                    Text("Off").tag(0)
                    Text("5 seconds").tag(5)
                }
                InterfacePickerRow("Disabled", selection: .constant(5)) {
                    Text("Off").tag(0)
                    Text("5 seconds").tag(5)
                }
                .interfacePresentedControlState(.disabled)
            }

            InterfaceSection("Text Field Row") {
                InterfaceTextFieldRow("Empty", prompt: "Bucket name", text: .constant(""))
                InterfaceTextFieldRow("Filled", text: .constant("upshot-captures"))
                InterfaceTextFieldRow("Focused", text: .constant("upshot-captures"))
                    .interfacePresentedControlState(.selected)
                InterfaceTextFieldRow("Disabled", text: .constant("upshot-captures"))
                    .interfacePresentedControlState(.disabled)
            }

            InterfaceSection("Folder Row", footer: "The folder name shows in the row. The full path shows in a tooltip.") {
                InterfaceFolderRow("Export folder", folderURL: folderURL) {}
                InterfaceFolderRow("Custom folder", folderURL: folderURL, onReset: {}) {}
                InterfaceFolderRow("Disabled", folderURL: folderURL) {}
                    .interfacePresentedControlState(.disabled)
            }

            InterfaceSection("Shortcut Row") {
                InterfaceShortcutRow("Assigned", keys: ["⌥", "1"], onRecord: {}, onClear: {})
                InterfaceShortcutRow("Hover", keys: ["⌥", "2"], onRecord: {}, onClear: {})
                    .interfacePresentedControlState(.hover)
                InterfaceShortcutRow("Customized", keys: ["⌃", "⇧", "3"], isCustomized: true, onRecord: {}, onClear: {}, onReset: {})
                InterfaceShortcutRow("Recording", keys: ["⌥", "4"], isRecording: true, onRecord: {}, onClear: {})
                InterfaceShortcutRow("Unassigned", keys: nil, onRecord: {}, onClear: {})
                InterfaceShortcutRow("Failure", keys: ["⇧", "⌘", "5"], failure: "macOS Screenshot uses this shortcut.", onRecord: {}, onClear: {})
                InterfaceShortcutRow("Disabled", keys: ["⌥", "6"], onRecord: {}, onClear: {})
                    .interfacePresentedControlState(.disabled)
            }

            InterfaceSection("Value with Unit") {
                InterfaceRow("Normal") {
                    InterfaceValueWithUnitField("Normal", value: .constant(30), unit: "days")
                }
                InterfaceRow("Focused") {
                    InterfaceValueWithUnitField("Focused", value: .constant(0), unit: "days")
                        .interfacePresentedControlState(.selected)
                }
                InterfaceRow("Disabled") {
                    InterfaceValueWithUnitField("Disabled", value: .constant(120), unit: "px")
                        .interfacePresentedControlState(.disabled)
                }
            }
        }
    }
}

private struct InterfaceStyleGalleryFloatingRegion: View {
    let backdrop: NSImage

    var body: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            InterfaceStyleGalleryRegionTitle(title: "Floating UI")
            VStack(alignment: .leading, spacing: Space.xxxl) {
                InterfaceStyleGalleryToolbarRow()
                InterfaceStyleGalleryControlRow()
                InterfaceStyleGalleryFlyoutRow()
                InterfaceStyleGalleryCardRow(backdrop: backdrop)
                InterfaceStyleGalleryToastRow()
            }
            .padding(Space.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                Image(nsImage: backdrop)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
}

private struct InterfaceStyleGalleryToolbarRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            InterfaceStyleGallerySample(state: "Toolbar: Area selected, Fullscreen normal, Window hover, Scrolling pressed, OCR disabled", onBackdrop: true) {
                InterfacePanel {
                    HStack(spacing: Space.xxs) {
                        InterfaceToolbarButton("Area", systemImage: "viewfinder", isSelected: true) {}
                        InterfaceToolbarButton("Fullscreen", systemImage: "display") {}
                        InterfaceToolbarButton("Window", systemImage: "macwindow") {}
                            .interfacePresentedControlState(.hover)
                        InterfaceToolbarButton("Scrolling", systemImage: "arrow.down.to.line") {}
                            .interfacePresentedControlState(.pressed)
                        InterfaceToolbarButton("Timer", systemImage: "timer") {}
                        InterfaceToolbarDivider()
                        InterfaceToolbarButton("OCR", systemImage: "textformat") {}
                            .interfacePresentedControlState(.disabled)
                        InterfaceToolbarDivider()
                        InterfaceToolbarButton("Recording", systemImage: "video") {}
                    }
                    .fixedSize()
                }
            }
            VStack(alignment: .leading, spacing: Space.l) {
                InterfaceStyleGallerySample(state: "Size fields: normal", onBackdrop: true) {
                    InterfaceSizeFieldsPill(width: .constant(608), height: .constant(455)) {
                        Text("Freeform")
                    }
                }
                InterfaceStyleGallerySample(state: "Size fields: width focused", onBackdrop: true) {
                    InterfaceSizeFieldsPill(width: .constant(1280), height: .constant(720)) {
                        Text("Freeform")
                    }
                    .interfacePresentedControlState(.selected)
                }
            }
        }
    }
}

private struct InterfaceStyleGalleryControlRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            InterfaceStyleGallerySample(state: "Icon-only toolbar: normal, hover, pressed, disabled", onBackdrop: true) {
                InterfacePanel {
                    HStack(spacing: Space.xxs) {
                        InterfaceToolbarButton("Stop Recording", systemImage: "stop.circle", labelPlacement: .hidden, tint: Palette.record) {}
                        InterfaceToolbarDivider()
                        InterfaceToolbarButton("Pause", systemImage: "pause.circle", labelPlacement: .hidden) {}
                            .interfacePresentedControlState(.hover)
                        InterfaceToolbarButton("Restart", systemImage: "arrow.counterclockwise", labelPlacement: .hidden) {}
                            .interfacePresentedControlState(.pressed)
                        InterfaceToolbarButton("Delete", systemImage: "trash", labelPlacement: .hidden) {}
                            .interfacePresentedControlState(.disabled)
                    }
                    .fixedSize()
                }
            }
            InterfaceStyleGallerySample(state: "Mode switch: All selected", onBackdrop: true) {
                InterfaceModeSwitch("Filter", selection: .constant("all"), options: Self.filterOptions, surface: .floating)
            }
            InterfaceStyleGallerySample(state: "Mode switch: Screenshots hover", onBackdrop: true) {
                InterfaceModeSwitch("Filter", selection: .constant("all"), options: Self.filterOptions, surface: .floating, presentedHoverValue: "screenshots")
            }
            InterfaceStyleGallerySample(state: "Mode switch: disabled", onBackdrop: true) {
                InterfaceModeSwitch("Filter", selection: .constant("all"), options: Self.filterOptions, surface: .floating)
                    .interfacePresentedControlState(.disabled)
            }
        }
    }

    static let filterOptions: [InterfaceModeSwitchOption<String>] = [
        InterfaceModeSwitchOption(value: "all", title: "All"),
        InterfaceModeSwitchOption(value: "screenshots", title: "Screenshots"),
        InterfaceModeSwitchOption(value: "videos", title: "Videos", systemImage: "video.fill")
    ]
}

private struct InterfaceStyleGalleryFlyoutRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            InterfaceStyleGallerySample(state: "Flyout rows: normal, hover, pressed, selected, disabled", onBackdrop: true) {
                InterfaceFlyoutMenu {
                    InterfaceFlyoutRow("Record Video", systemImage: "video.fill", keyHint: "↩") {}
                    InterfaceFlyoutRow("Record GIF", systemImage: "photo.stack", keyHint: "⌥↩") {}
                        .interfacePresentedControlState(.hover)
                    InterfaceFlyoutRow("Record in Studio Mode", systemImage: "film", keyHint: "⇧↩") {}
                        .interfacePresentedControlState(.pressed)
                    InterfaceFlyoutDivider()
                    InterfaceFlyoutRow("Capture Text", systemImage: "text.viewfinder", keyHint: "⌥5", isHighlighted: true) {}
                    InterfaceFlyoutRow("Scrolling Capture", systemImage: "arrow.down.to.line", keyHint: "⌥7") {}
                        .interfacePresentedControlState(.disabled)
                }
            }
        }
    }
}

private struct InterfaceStyleGalleryCardRow: View {
    let backdrop: NSImage
    private let states: [InterfacePresentedControlState] = [.normal, .hover, .pressed, .selected, .disabled]

    var body: some View {
        HStack(alignment: .top, spacing: Space.xxl) {
            ForEach(states) { state in
                InterfaceStyleGallerySample(state: "Card: \(state.title)", onBackdrop: true) {
                    InterfaceCard(isSelected: state == .selected, padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            Image(nsImage: backdrop)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 176, height: 110)
                                .clipped()
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Screenshot")
                                    .font(.dsBodyEmphasis)
                                    .foregroundStyle(Palette.label)
                                Text("1280 × 800")
                                    .font(.dsCaption)
                                    .foregroundStyle(Palette.secondaryLabel)
                            }
                            .padding(InterfaceMetrics.cardPadding)
                        }
                    }
                    .interfacePresentedControlState(state == .selected ? nil : state)
                }
            }
        }
    }
}

private struct InterfaceStyleGalleryToastRow: View {
    var body: some View {
        HStack(alignment: .top, spacing: Space.xl) {
            InterfaceStyleGallerySample(state: "Toast: neutral", onBackdrop: true) {
                InterfaceToast("Copied to Clipboard", systemImage: "doc.on.clipboard")
            }
            InterfaceStyleGallerySample(state: "Toast: success", onBackdrop: true) {
                InterfaceToast("Uploaded", detail: "Link copied", systemImage: "checkmark.circle.fill", tone: .success)
            }
            InterfaceStyleGallerySample(state: "Toast: failure with action", onBackdrop: true) {
                InterfaceToast("Upload Failed", detail: "The server did not respond.", systemImage: "exclamationmark.triangle.fill", tone: .failure, actionTitle: "Retry") {}
            }
            InterfaceStyleGallerySample(state: "Toast: action hover", onBackdrop: true) {
                InterfaceToast("No Text Found", systemImage: "text.viewfinder", actionTitle: "Undo") {}
                    .interfacePresentedControlState(.hover)
            }
        }
    }
}

private struct InterfaceStyleGalleryWindowModeSwitch: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            InterfaceStyleGalleryComponentTitle(title: "Mode Switch in a Window")
            HStack(alignment: .top, spacing: Space.l) {
                InterfaceStyleGallerySample(state: "Medium selected") {
                    InterfaceModeSwitch("Length", selection: .constant("medium"), options: Self.lengthOptions)
                }
                InterfaceStyleGallerySample(state: "Long hover") {
                    InterfaceModeSwitch("Length", selection: .constant("medium"), options: Self.lengthOptions, presentedHoverValue: "long")
                }
                InterfaceStyleGallerySample(state: "Disabled") {
                    InterfaceModeSwitch("Length", selection: .constant("medium"), options: Self.lengthOptions)
                        .interfacePresentedControlState(.disabled)
                }
            }
        }
    }

    static let lengthOptions: [InterfaceModeSwitchOption<String>] = [
        InterfaceModeSwitchOption(value: "short", title: "Short"),
        InterfaceModeSwitchOption(value: "medium", title: "Medium"),
        InterfaceModeSwitchOption(value: "long", title: "Long")
    ]
}
