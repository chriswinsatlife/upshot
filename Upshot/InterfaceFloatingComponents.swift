import AppKit
import SwiftUI

enum InterfacePanelShape: Sendable {
    case panel
    case flyout
    case pill

    var cornerRadius: CGFloat {
        switch self {
        case .panel: Radius.panel
        case .flyout: Radius.flyout
        case .pill: InterfaceMetrics.toolbarButtonHeight
        }
    }
}

extension View {
    func interfacePanelSurface(_ shape: InterfacePanelShape = .panel) -> some View {
        interfacePanelSurface(cornerRadius: shape.cornerRadius)
    }

    func interfacePanelSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return background(Palette.floatingPanelBase, in: shape)
            .glassEffect(.regular, in: shape)
            .overlay {
                shape
                    .strokeBorder(Palette.floatingStroke, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
    }
}

struct InterfacePanel<Content: View>: View {
    var shape: InterfacePanelShape = .panel
    var padding: CGFloat = InterfaceMetrics.floatingPanelPadding
    @ViewBuilder var content: () -> Content

    init(_ shape: InterfacePanelShape = .panel, padding: CGFloat = InterfaceMetrics.floatingPanelPadding, @ViewBuilder content: @escaping () -> Content) {
        self.shape = shape
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .interfacePanelSurface(shape)
    }
}

struct InterfaceToolbarDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.floatingDivider)
            .frame(width: 1)
            .padding(.vertical, InterfaceMetrics.floatingDividerInset)
            .accessibilityHidden(true)
    }
}

enum InterfaceToolbarLabelPlacement: Sendable {
    case belowIcon
    case hidden
}

struct InterfaceToolbarButton: View {
    let title: String
    let systemImage: String
    var isSelected = false
    var labelPlacement: InterfaceToolbarLabelPlacement = .belowIcon
    var tint: Color? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(
        _ title: String,
        systemImage: String,
        isSelected: Bool = false,
        labelPlacement: InterfaceToolbarLabelPlacement = .belowIcon,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.labelPlacement = labelPlacement
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: InterfaceMetrics.toolbarIconToLabelSpacing) {
                Image(systemName: systemImage)
                    .font(.system(size: InterfaceMetrics.toolbarIconPointSize, weight: .regular))
                    .foregroundStyle(iconStyle)
                    .frame(height: 20)
                if labelPlacement == .belowIcon {
                    Text(title)
                        .font(.dsToolbarLabel)
                        .foregroundStyle(titleStyle)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .padding(.horizontal, Space.m)
            .frame(
                minWidth: labelPlacement == .belowIcon ? InterfaceMetrics.toolbarButtonMinimumWidth : 40,
                minHeight: labelPlacement == .belowIcon ? InterfaceMetrics.toolbarButtonHeight : 40
            )
        }
        .buttonStyle(InterfaceFloatingButtonStyle(isSelected: isSelected, cornerRadius: Radius.toolbarButton))
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var iconStyle: Color {
        guard isEnabled else { return Palette.disabledLabel }
        return tint ?? Palette.label
    }

    private var titleStyle: Color {
        guard isEnabled else { return Palette.disabledLabel }
        return isSelected ? Palette.label : Palette.secondaryLabel
    }
}

struct InterfaceFloatingButtonStyle: ButtonStyle {
    var isSelected = false
    var cornerRadius: CGFloat = Radius.toolbarButton

    func makeBody(configuration: Configuration) -> some View {
        InterfaceFloatingButtonBody(configuration: configuration, isSelected: isSelected, cornerRadius: cornerRadius)
    }
}

private struct InterfaceFloatingButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let cornerRadius: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    var body: some View {
        let interaction = presentedState.resolvedInteraction(isHovering: isHovering, isPressed: configuration.isPressed)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .background(fill(interaction), in: shape)
            .contentShape(shape)
            .scaleEffect(interaction.isPressed && isEnabled && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: interaction.isPressed)
            .onHover { isHovering = $0 }
    }

    private func fill(_ interaction: InterfaceInteractionState) -> Color {
        guard isEnabled else { return .clear }
        if interaction.isPressed { return Palette.floatingPressedFill }
        if isSelected { return Palette.floatingSelectionFill }
        return interaction.isHovered ? Palette.floatingHoverFill : .clear
    }
}

struct InterfaceModeSwitchOption<Value: Hashable>: Identifiable {
    let value: Value
    let title: String
    var systemImage: String? = nil

    var id: Value { value }
}

struct InterfaceModeSwitch<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [InterfaceModeSwitchOption<Value>]

    @Namespace private var selectionNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String, selection: Binding<Value>, options: [InterfaceModeSwitchOption<Value>]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: Space.xxs) {
            ForEach(options) { option in
                InterfaceModeSwitchSegment(
                    option: option,
                    isSelected: option.value == selection,
                    selectionNamespace: selectionNamespace
                ) {
                    withAnimation(reduceMotion ? nil : .morphQuick) {
                        selection = option.value
                    }
                }
            }
        }
        .padding(Space.xxs)
        .background(Palette.controlFill, in: Capsule())
        .fixedSize()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

private struct InterfaceModeSwitchSegment<Value: Hashable>: View {
    let option: InterfaceModeSwitchOption<Value>
    let isSelected: Bool
    let selectionNamespace: Namespace.ID
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState
    @State private var isHovering = false

    var body: some View {
        let interaction = presentedState.resolvedInteraction(isHovering: isHovering, isPressed: false)
        Button(action: action) {
            HStack(spacing: Space.xs) {
                if let systemImage = option.systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(option.title)
                    .font(.dsSegment)
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, Space.m + 2)
            .frame(height: InterfaceMetrics.modeSwitchHeight - Space.xxs * 2)
            .background {
                if isSelected {
                    Capsule()
                        .fill(isEnabled ? Palette.accent : Palette.controlHoverFill)
                        .matchedGeometryEffect(id: "selectedSegment", in: selectionNamespace)
                } else if interaction.isHovered, isEnabled {
                    Capsule().fill(Palette.floatingHoverFill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var foreground: Color {
        guard isEnabled else { return Palette.disabledLabel }
        return isSelected ? Palette.onAccent : Palette.label
    }
}

struct InterfaceSizeFieldsPill<AspectMenu: View>: View {
    @Binding var width: Int
    @Binding var height: Int
    var aspectSystemImage = "crop"
    @ViewBuilder var aspectMenu: () -> AspectMenu

    init(width: Binding<Int>, height: Binding<Int>, aspectSystemImage: String = "crop", @ViewBuilder aspectMenu: @escaping () -> AspectMenu) {
        self._width = width
        self._height = height
        self.aspectSystemImage = aspectSystemImage
        self.aspectMenu = aspectMenu
    }

    var body: some View {
        HStack(spacing: Space.s) {
            InterfaceSizeField(title: "Width", value: $width)
            Text("×")
                .font(.dsBody)
                .foregroundStyle(Palette.secondaryLabel)
                .accessibilityHidden(true)
            InterfaceSizeField(title: "Height", value: $height)
            InterfaceToolbarDivider()
                .padding(.horizontal, Space.xxs)
            Menu {
                aspectMenu()
            } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: aspectSystemImage)
                        .font(.system(size: 15, weight: .regular))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Palette.secondaryLabel)
                }
                .foregroundStyle(Palette.label)
                .padding(.horizontal, Space.s)
                .frame(height: InterfaceMetrics.sizeFieldHeight)
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.field))
            .fixedSize()
            .help("Aspect Ratio")
            .accessibilityLabel("Aspect Ratio")
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(InterfaceMetrics.floatingPanelPadding)
        .interfacePanelSurface(cornerRadius: Radius.nested(inner: Radius.field, padding: InterfaceMetrics.floatingPanelPadding))
    }
}

private struct InterfaceSizeField: View {
    let title: String
    @Binding var value: Int

    @FocusState private var isFocused: Bool
    @Environment(\.interfacePresentedControlState) private var presentedState
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let showsFocus = presentedState.map { $0 == .selected && title == "Width" } ?? isFocused
        TextField("", value: $value, format: .number.grouping(.never))
            .labelsHidden()
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium).monospacedDigit())
            .multilineTextAlignment(.center)
            .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
            .focused($isFocused)
            .frame(width: InterfaceMetrics.sizeFieldWidth, height: InterfaceMetrics.sizeFieldHeight)
            .background(Palette.controlFill, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(Palette.accent, lineWidth: 2)
                    .opacity(showsFocus ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .accessibilityLabel(title)
    }
}

struct InterfaceFlyoutMenu<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(InterfaceMetrics.floatingPanelPadding - 1)
        .frame(minWidth: InterfaceMetrics.flyoutMinimumWidth)
        .fixedSize()
        .interfacePanelSurface(.flyout)
    }
}

struct InterfaceFlyoutDivider: View {
    var body: some View {
        Rectangle()
            .fill(Palette.floatingDivider)
            .frame(height: 1)
            .padding(.horizontal, Space.m + 1)
            .padding(.vertical, Space.xs)
            .accessibilityHidden(true)
    }
}

struct InterfaceFlyoutRow: View {
    let title: String
    let systemImage: String
    var keyHint: String? = nil
    var isHighlighted = false
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    init(_ title: String, systemImage: String, keyHint: String? = nil, isHighlighted: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.keyHint = keyHint
        self.isHighlighted = isHighlighted
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.m + 2) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: InterfaceMetrics.flyoutIconSlotWidth)
                Text(title)
                    .font(.dsBodyEmphasis)
                    .lineLimit(1)
                Spacer(minLength: Space.xl)
                if let keyHint {
                    Text(keyHint)
                        .font(.system(size: 12.5))
                        .foregroundStyle(isEnabled ? Palette.secondaryLabel : Palette.disabledLabel)
                        .accessibilityLabel("Shortcut \(keyHint)")
                }
            }
            .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
            .padding(.horizontal, Space.m + 1)
            .frame(height: InterfaceMetrics.flyoutRowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(InterfaceFloatingButtonStyle(
            isSelected: isHighlighted,
            cornerRadius: Radius.flyout - (InterfaceMetrics.floatingPanelPadding - 1)
        ))
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }
}

struct InterfaceCard<Content: View>: View {
    var isSelected = false
    var padding: CGFloat = InterfaceMetrics.cardPadding
    @ViewBuilder var content: () -> Content

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.interfacePresentedControlState) private var presentedState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    init(isSelected: Bool = false, padding: CGFloat = InterfaceMetrics.cardPadding, @ViewBuilder content: @escaping () -> Content) {
        self.isSelected = isSelected
        self.padding = padding
        self.content = content
    }

    var body: some View {
        let interaction = presentedState.resolvedInteraction(isHovering: isHovering, isPressed: false)
        let isPressed = presentedState == .pressed
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        content()
            .padding(padding)
            .background(Palette.panel, in: shape)
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(interaction.isHovered && isEnabled ? Palette.strongHairline : Palette.floatingStroke, lineWidth: 0.5)
                    .allowsHitTesting(false)
            }
            .overlay {
                shape
                    .inset(by: -3)
                    .strokeBorder(Palette.accent, lineWidth: 2.5)
                    .opacity(isSelected ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(interaction.isHovered ? 0.22 : 0.16), radius: interaction.isHovered ? 12 : 8, y: interaction.isHovered ? 5 : 3)
            .opacity(isEnabled ? 1 : 0.5)
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: interaction)
            .onHover { isHovering = $0 }
    }
}

enum InterfaceToastTone: Sendable {
    case neutral
    case success
    case failure

    var color: Color {
        switch self {
        case .neutral: Palette.label
        case .success: Palette.success
        case .failure: Palette.destructive
        }
    }
}

struct InterfaceToast: View {
    let title: String
    var detail: String? = nil
    let systemImage: String
    var tone: InterfaceToastTone = .neutral
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    init(
        _ title: String,
        detail: String? = nil,
        systemImage: String,
        tone: InterfaceToastTone = .neutral,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(spacing: Space.m + 2) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tone.color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.dsBodyEmphasis)
                    .foregroundStyle(Palette.label)
                if let detail {
                    Text(detail)
                        .font(.dsCaption)
                        .foregroundStyle(Palette.secondaryLabel)
                }
            }
            .lineLimit(1)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.interfaceAction)
                    .padding(.leading, Space.xs)
            }
        }
        .padding(.leading, Space.l)
        .padding(.trailing, actionTitle == nil ? Space.l + 2 : Space.m)
        .padding(.vertical, Space.s + 1)
        .frame(minHeight: InterfaceMetrics.toastMinimumHeight)
        .fixedSize()
        .interfacePanelSurface(.flyout)
        .accessibilityElement(children: .combine)
    }
}
