import AppKit
import UniformTypeIdentifiers
import SwiftUI

struct InterfaceFormPage<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        Form { content() }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.top, Space.m, for: .scrollContent)
            .toggleStyle(.ink)
            .buttonStyle(.interfaceAction)
    }
}

struct InterfaceSectionHeader: View {
    let title: String
    var detail: String? = nil

    init(_ title: String, detail: String? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.rowLabelToDetailSpacing) {
            Text(title)
                .font(.dsHeadline)
                .foregroundStyle(Palette.label)
                .accessibilityAddTraits(.isHeader)
            if let detail {
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InterfaceSection<Content: View>: View {
    let title: String?
    var detail: String? = nil
    var footer: String? = nil
    @ViewBuilder var content: () -> Content

    init(_ title: String?, detail: String? = nil, footer: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.detail = detail
        self.footer = footer
        self.content = content
    }

    var body: some View {
        Section {
            content()
        } header: {
            if let title {
                InterfaceSectionHeader(title, detail: detail)
            }
        } footer: {
            if let footer {
                Text(footer)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct InterfaceRowLabel: View {
    let title: String
    var detail: String? = nil
    var detailIsCritical = false

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, detail: String? = nil, detailIsCritical: Bool = false) {
        self.title = title
        self.detail = detail
        self.detailIsCritical = detailIsCritical
    }

    var body: some View {
        VStack(alignment: .leading, spacing: InterfaceMetrics.rowLabelToDetailSpacing) {
            Text(title)
                .font(.dsBody)
                .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
            if let detail {
                Text(detail)
                    .font(.dsCaption)
                    .foregroundStyle(detailIsCritical ? Palette.destructive : Palette.secondaryLabel)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct InterfaceRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    var systemImage: String? = nil
    var detailIsCritical = false
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        detail: String? = nil,
        systemImage: String? = nil,
        detailIsCritical: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.detailIsCritical = detailIsCritical
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .center, spacing: InterfaceMetrics.rowControlSpacing) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isEnabled ? Palette.secondaryLabel : Palette.disabledLabel)
                    .frame(width: 18)
            }
            InterfaceRowLabel(title, detail: detail, detailIsCritical: detailIsCritical)
            Spacer(minLength: Space.l)
            trailing()
        }
        .frame(minHeight: InterfaceMetrics.rowMinimumHeight)
    }
}

struct InterfaceToggleRow: View {
    let title: String
    var detail: String? = nil
    @Binding var isOn: Bool

    init(_ title: String, detail: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.detail = detail
        self._isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            InterfaceRowLabel(title, detail: detail)
        }
        .toggleStyle(.ink)
        .frame(minHeight: InterfaceMetrics.rowMinimumHeight)
    }
}

struct InterfacePickerRow<Selection: Hashable, Options: View>: View {
    let title: String
    var detail: String? = nil
    @Binding var selection: Selection
    @ViewBuilder var options: () -> Options

    init(_ title: String, detail: String? = nil, selection: Binding<Selection>, @ViewBuilder options: @escaping () -> Options) {
        self.title = title
        self.detail = detail
        self._selection = selection
        self.options = options
    }

    var body: some View {
        Picker(selection: $selection) {
            options()
        } label: {
            InterfaceRowLabel(title, detail: detail)
        }
        .pickerStyle(.menu)
        .frame(minHeight: InterfaceMetrics.rowMinimumHeight)
    }
}

struct InterfaceTextFieldRow: View {
    let title: String
    var detail: String? = nil
    var prompt: String = ""
    var fieldWidth: CGFloat = 220
    @Binding var text: String

    init(_ title: String, detail: String? = nil, prompt: String = "", fieldWidth: CGFloat = 220, text: Binding<String>) {
        self.title = title
        self.detail = detail
        self.prompt = prompt
        self.fieldWidth = fieldWidth
        self._text = text
    }

    var body: some View {
        InterfaceRow(title, detail: detail) {
            TextField("", text: $text, prompt: Text(prompt))
                .labelsHidden()
                .font(.dsBody)
                .multilineTextAlignment(.leading)
                .interfaceFieldChrome()
                .frame(width: fieldWidth)
                .accessibilityLabel(title)
        }
    }
}

struct InterfaceFolderRow: View {
    let title: String
    var detail: String? = nil
    let folderURL: URL
    var onReset: (() -> Void)? = nil
    let onChoose: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, detail: String? = nil, folderURL: URL, onReset: (() -> Void)? = nil, onChoose: @escaping () -> Void) {
        self.title = title
        self.detail = detail
        self.folderURL = folderURL
        self.onReset = onReset
        self.onChoose = onChoose
    }

    var body: some View {
        InterfaceRow(title, detail: detail) {
            HStack(spacing: Space.xs + 1) {
                Image(nsImage: NSWorkspace.shared.icon(for: .folder))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 16, height: 16)
                    .opacity(isEnabled ? 1 : 0.5)
                Text(folderDisplayName)
                    .font(.dsBody)
                    .foregroundStyle(isEnabled ? Palette.secondaryLabel : Palette.disabledLabel)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(folderURL.path)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(folderDisplayName)
            .accessibilityValue(folderURL.path)

            if let onReset {
                InspectorResetButton(help: "Use the default folder", action: onReset)
            }

            Button("Choose…", action: onChoose)
                .buttonStyle(.interfaceAction)
        }
    }

    private var folderDisplayName: String {
        FileManager.default.displayName(atPath: folderURL.path)
    }
}

struct InterfaceShortcutRow: View {
    let title: String
    var detail: String? = nil
    let keys: [String]?
    var isRecording = false
    var isCustomized = false
    var failure: String? = nil
    let onRecord: () -> Void
    var onClear: (() -> Void)? = nil
    var onReset: (() -> Void)? = nil

    init(
        _ title: String,
        detail: String? = nil,
        keys: [String]?,
        isRecording: Bool = false,
        isCustomized: Bool = false,
        failure: String? = nil,
        onRecord: @escaping () -> Void,
        onClear: (() -> Void)? = nil,
        onReset: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.keys = keys
        self.isRecording = isRecording
        self.isCustomized = isCustomized
        self.failure = failure
        self.onRecord = onRecord
        self.onClear = onClear
        self.onReset = onReset
    }

    var body: some View {
        InterfaceRow(title, detail: failure ?? detail, detailIsCritical: failure != nil) {
            if isCustomized, !isRecording, let onReset {
                InspectorResetButton(help: "Restore the default shortcut", action: onReset)
            }
            InterfaceShortcutField(keys: keys, isRecording: isRecording, onRecord: onRecord, onClear: onClear)
        }
    }
}

struct InterfaceShortcutField: View {
    let keys: [String]?
    var isRecording = false
    let onRecord: () -> Void
    var onClear: (() -> Void)? = nil

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState
    @State private var isHovering = false

    private var showsClearButton: Bool { keys != nil && !isRecording && onClear != nil }

    var body: some View {
        let interaction = presentedState.resolvedInteraction(isHovering: isHovering, isPressed: false)
        ZStack(alignment: .trailing) {
            Button(action: onRecord) {
                HStack(spacing: 3) {
                    if isRecording {
                        Text("Press keys…")
                            .foregroundStyle(Palette.accent)
                    } else if let keys {
                        ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                            Text(key)
                        }
                        .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
                    } else {
                        Text("Record Shortcut")
                            .foregroundStyle(isEnabled ? Palette.secondaryLabel : Palette.disabledLabel)
                    }
                }
                .font(.dsBody)
                .lineLimit(1)
                .padding(.leading, InterfaceMetrics.fieldHorizontalPadding + 2)
                .padding(.trailing, showsClearButton ? 24 : InterfaceMetrics.fieldHorizontalPadding + 2)
                .frame(minWidth: 112, minHeight: InterfaceMetrics.controlHeight)
                .background(
                    interaction.isHovered && isEnabled ? Palette.controlHoverFill : Palette.fieldFill,
                    in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                        .strokeBorder(isRecording ? Palette.accent : Palette.fieldStroke, lineWidth: isRecording ? 2 : 1)
                }
                .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { isHovering = $0 }
            .accessibilityLabel(isRecording ? "Recording shortcut" : (keys?.joined() ?? "Record Shortcut"))

            if showsClearButton, let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryLabel)
                        .frame(width: 20, height: InterfaceMetrics.controlHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .help("Clear shortcut")
                .accessibilityLabel("Clear shortcut")
            }
        }
        .fixedSize()
    }
}

struct InterfaceActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        InterfaceActionButtonBody(configuration: configuration)
    }
}

extension ButtonStyle where Self == InterfaceActionButtonStyle {
    static var interfaceAction: InterfaceActionButtonStyle { InterfaceActionButtonStyle() }
}

private struct InterfaceActionButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let interaction = presentedState.resolvedInteraction(isHovering: isHovering, isPressed: configuration.isPressed)
        let isDestructive = configuration.role == .destructive
        configuration.label
            .labelStyle(InterfaceActionLabelStyle())
            .font(.dsBody)
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(foreground(isDestructive: isDestructive))
            .padding(.horizontal, InterfaceMetrics.actionButtonHorizontalPadding)
            .frame(height: InterfaceMetrics.controlHeight)
            .background(fill(isDestructive: isDestructive, interaction: interaction), in: shape)
            .contentShape(shape)
            .scaleEffect(interaction.isPressed && isEnabled && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: interaction.isPressed)
            .onHover { isHovering = $0 }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }

    private func foreground(isDestructive: Bool) -> Color {
        if isDestructive { return Palette.destructive.opacity(isEnabled ? 1 : 0.45) }
        return isEnabled ? Palette.label : Palette.disabledLabel
    }

    private func fill(isDestructive: Bool, interaction: InterfaceInteractionState) -> Color {
        guard isEnabled else { return isDestructive ? Palette.destructiveFill.opacity(0.6) : Palette.controlFill.opacity(0.6) }
        if isDestructive {
            if interaction.isPressed { return Palette.destructivePressedFill }
            return interaction.isHovered ? Palette.destructiveHoverFill : Palette.destructiveFill
        }
        if interaction.isPressed { return Palette.controlPressedFill }
        return interaction.isHovered ? Palette.controlHoverFill : Palette.controlFill
    }
}

private struct InterfaceActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: InterfaceMetrics.actionButtonIconToLabelSpacing) {
            configuration.icon
                .font(.system(size: 11.5, weight: .semibold))
            configuration.title
        }
    }
}

struct InterfaceActionButton: View {
    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }

    var body: some View {
        Button(role: role, action: action) {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }
        .buttonStyle(.interfaceAction)
    }
}

enum InterfaceUnitSpacing: Sendable {
    case wordSpace
    case none

    var separator: String {
        switch self {
        case .wordSpace: " "
        case .none: ""
        }
    }
}

struct InterfaceValueWithUnitLabel: View {
    let value: String
    let unit: String
    var unitSpacing: InterfaceUnitSpacing = .wordSpace

    var body: some View {
        Text("\(Text(value).foregroundStyle(Palette.label))\(Text(unitSpacing.separator + unit).foregroundStyle(Palette.secondaryLabel))")
            .font(.dsFieldNumeric)
            .lineLimit(1)
            .fixedSize()
    }
}

struct InterfaceValueWithUnitField: View {
    let title: String
    @Binding var value: Int
    let unit: String
    var unitSpacing: InterfaceUnitSpacing = .wordSpace
    var range: ClosedRange<Int> = 0...Int.max
    var minimumDigitCount = 2

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        value: Binding<Int>,
        unit: String,
        unitSpacing: InterfaceUnitSpacing = .wordSpace,
        range: ClosedRange<Int> = 0...Int.max,
        minimumDigitCount: Int = 2
    ) {
        self.title = title
        self._value = value
        self.unit = unit
        self.unitSpacing = unitSpacing
        self.range = range
        self.minimumDigitCount = minimumDigitCount
    }

    var body: some View {
        HStack(spacing: 0) {
            TextField("", value: clampedValue, format: .number.grouping(.never))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.dsFieldNumeric)
                .multilineTextAlignment(.trailing)
                .frame(width: digitColumnWidth)
                .accessibilityLabel(title)
                .accessibilityValue("\(value) \(unit)")
            Text(unitSpacing.separator + unit)
                .font(.dsBody)
                .foregroundStyle(isEnabled ? Palette.secondaryLabel : Palette.disabledLabel)
                .fixedSize()
                .accessibilityHidden(true)
        }
        .interfaceFieldChrome()
        .fixedSize()
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { value = min(max($0, range.lowerBound), range.upperBound) }
        )
    }

    private var digitColumnWidth: CGFloat {
        let digitCount = max(minimumDigitCount, String(value).count)
        return CGFloat(digitCount) * 7.6 + 2
    }
}

private struct InterfaceFieldChrome: ViewModifier {
    @FocusState private var isFocused: Bool
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState

    func body(content: Content) -> some View {
        let showsFocus = presentedState.map { $0 == .selected } ?? isFocused
        content
            .textFieldStyle(.plain)
            .focused($isFocused)
            .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
            .padding(.horizontal, InterfaceMetrics.fieldHorizontalPadding)
            .frame(minHeight: InterfaceMetrics.controlHeight)
            .background(Palette.fieldFill.opacity(isEnabled ? 1 : 0.5), in: RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(showsFocus ? Palette.accent : Palette.fieldStroke, lineWidth: showsFocus ? 2 : 1)
                    .allowsHitTesting(false)
            }
    }
}

extension View {
    func interfaceFieldChrome() -> some View {
        modifier(InterfaceFieldChrome())
    }
}

struct InterfaceSidebar<Content: View>: View {
    var searchPrompt = "Search"
    var searchText: Binding<String>? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let searchText {
                InterfaceSidebarSearchField(prompt: searchPrompt, text: searchText)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    content()
                }
            }
            .scrollIndicators(.never)
        }
        .padding(.horizontal, Space.m + 2)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

struct InterfaceSidebarSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: () -> Void = {}

    @FocusState private var isFocused: Bool
    @Environment(\.interfacePresentedControlState) private var presentedState

    var body: some View {
        let showsFocus = presentedState.map { $0 == .selected } ?? isFocused
        HStack(spacing: Space.s) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.secondaryLabel)
            TextField("", text: $text, prompt: Text(prompt))
                .labelsHidden()
                .textFieldStyle(.plain)
                .font(.dsBody)
                .focused($isFocused)
                .onSubmit(onSubmit)
                .onExitCommand { text = "" }
                .accessibilityLabel(prompt)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.tertiaryLabel)
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, Space.m + 1)
        .frame(height: InterfaceMetrics.searchFieldHeight)
        .background(Palette.controlFill, in: Capsule())
        .overlay {
            Capsule()
                .strokeBorder(Palette.accent, lineWidth: 2)
                .opacity(showsFocus ? 1 : 0)
                .allowsHitTesting(false)
        }
    }
}

struct InterfaceSidebarGroupHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.dsGroupLabel)
            .foregroundStyle(Palette.secondaryLabel)
            .padding(.horizontal, InterfaceMetrics.sidebarRowHorizontalPadding)
            .padding(.top, InterfaceMetrics.sidebarGroupSpacing)
            .padding(.bottom, Space.xs)
            .accessibilityAddTraits(.isHeader)
    }
}

enum InterfaceSidebarIcon {
    case symbol(String, tint: Color)
    case image(NSImage)
}

struct InterfaceSidebarIconTile: View {
    let icon: InterfaceSidebarIcon

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.sidebarIconTile, style: .continuous)
        Group {
            switch icon {
            case .symbol(let systemImage, let tint):
                shape
                    .fill(tint.gradient)
                    .overlay {
                        shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    }
                    .overlay {
                        Image(systemName: systemImage)
                            .font(.system(size: InterfaceMetrics.sidebarIconGlyphPointSize, weight: .semibold))
                            .symbolVariant(.fill)
                            .foregroundStyle(Color.white)
                    }
            case .image(let image):
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: InterfaceMetrics.sidebarIconTileSize, height: InterfaceMetrics.sidebarIconTileSize)
        .saturation(isEnabled ? 1 : 0)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityHidden(true)
    }
}

enum InterfaceSidebarTint {
    static let gray = Color(nsColor: .systemGray)
    static let blue = Color(nsColor: .systemBlue)
    static let red = Color(nsColor: .systemRed)
    static let orange = Color(nsColor: .systemOrange)
    static let yellow = Color(nsColor: .systemYellow)
    static let green = Color(nsColor: .systemGreen)
    static let teal = Color(nsColor: .systemTeal)
    static let indigo = Color(nsColor: .systemIndigo)
    static let purple = Color(nsColor: .systemPurple)
    static let pink = Color(nsColor: .systemPink)
}

struct InterfaceSidebarRow: View {
    let title: String
    let icon: InterfaceSidebarIcon
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String, tint: Color = InterfaceSidebarTint.gray, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.init(title, icon: .symbol(systemImage, tint: tint), count: count, isSelected: isSelected, action: action)
    }

    init(_ title: String, icon: InterfaceSidebarIcon, count: Int? = nil, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.count = count
        self.isSelected = isSelected
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            InterfaceSidebarRowLabel(title: title, icon: icon, count: count)
        }
        .buttonStyle(InterfaceSidebarRowButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct InterfaceSidebarRowLabel: View {
    let title: String
    let icon: InterfaceSidebarIcon
    var count: Int? = nil

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: InterfaceMetrics.sidebarIconToLabelSpacing) {
            InterfaceSidebarIconTile(icon: icon)
            Text(title)
                .font(.dsBody)
                .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: Space.s)
            if let count {
                Text(count, format: .number)
                    .font(.dsCallout.monospacedDigit())
                    .foregroundStyle(isEnabled ? Palette.secondaryLabel : Palette.disabledLabel)
            }
        }
        .padding(.horizontal, InterfaceMetrics.sidebarRowHorizontalPadding)
        .frame(height: InterfaceMetrics.sidebarRowHeight)
    }
}

private struct InterfaceSidebarRowButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        InterfaceSidebarRowButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct InterfaceSidebarRowButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState
    @State private var isHovering = false

    var body: some View {
        let interaction = presentedState.resolvedInteraction(isHovering: isHovering, isPressed: configuration.isPressed)
        configuration.label
            .background(fill(interaction), in: RoundedRectangle(cornerRadius: Radius.sidebarRow, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Radius.sidebarRow, style: .continuous))
            .onHover { isHovering = $0 }
    }

    private func fill(_ interaction: InterfaceInteractionState) -> Color {
        guard isEnabled else { return .clear }
        if interaction.isPressed { return Palette.sidebarPressedFill }
        if isSelected { return Palette.sidebarSelectionFill }
        return interaction.isHovered ? Palette.sidebarHoverFill : .clear
    }
}
