
import AppKit
import SwiftUI

enum GlassMetrics {
    static let containerSpacing: CGFloat = 6
    static let gap: CGFloat = 8
    static let buttonSize: CGFloat = 30
    static let compactHeight: CGFloat = 26
    static let actionHeight: CGFloat = 34
    static let symbolSize: CGFloat = 12
}

private extension Glass {
    static func upshot(isInked: Bool, tint: Color?, isEnabled: Bool) -> Glass {
        var glass = Glass.regular
        if let tint {
            glass = glass.tint(tint)
        } else if isInked {
            glass = glass.tint(Palette.accent.opacity(isEnabled ? 1 : 0.35))
        }
        return glass.interactive(isEnabled)
    }
}

private func glassForeground(isInked: Bool, tint: Color?, isEnabled: Bool) -> Color {
    if tint != nil { return .white.opacity(isEnabled ? 1 : 0.5) }
    if isInked { return Palette.onAccent.opacity(isEnabled ? 1 : 0.5) }
    return isEnabled ? Palette.label : Palette.disabledLabel
}


struct GlassIconButton: View {
    let systemImage: String
    let help: String
    var size: CGFloat = GlassMetrics.buttonSize
    var symbolSize: CGFloat = GlassMetrics.symbolSize
    var isOn = false
    var tint: Color? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(glassForeground(isInked: isOn, tint: tint, isEnabled: isEnabled))
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: size, height: size)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.upshot(isInked: isOn, tint: tint, isEnabled: isEnabled), in: .circle)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

struct GlassCapsuleButton: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = GlassMetrics.buttonSize
    var isProminent = false
    var tint: Color? = nil
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: height < 28 ? 10.5 : GlassMetrics.symbolSize - 1, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace.downUp))
                }
                Text(title)
                    .font(.system(size: height < 28 ? 11.5 : 12, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(glassForeground(isInked: isProminent, tint: tint, isEnabled: isEnabled))
            .padding(.horizontal, height < 28 ? 11 : 13)
            .frame(height: height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.upshot(isInked: isProminent, tint: tint, isEnabled: isEnabled), in: .capsule)
    }
}

struct GlassMenuButton<Content: View>: View {
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = GlassMetrics.buttonSize
    var help: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Menu {
            content()
        } label: {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: GlassMetrics.symbolSize - 1, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: height < 28 ? 11.5 : 12, weight: .semibold))
                    .lineLimit(1)
                    .contentTransition(.interpolate)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .foregroundStyle(isEnabled ? Palette.label : Palette.disabledLabel)
            .padding(.horizontal, height < 28 ? 11 : 13)
            .frame(height: height)
            .contentShape(Capsule())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .glassEffect(.regular.interactive(isEnabled), in: .capsule)
        .help(help ?? title)
    }
}

struct GlassConfirmButton: View {
    let systemImage: String
    let help: String
    var confirmation: String = "Copied"
    var size: CGFloat = GlassMetrics.buttonSize
    let action: () -> Void

    @State private var confirmed = false
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        GlassIconButton(
            systemImage: confirmed ? "checkmark" : systemImage,
            help: confirmed ? confirmation : help,
            size: size
        ) {
            action()
            confirmed = true
            resetTask?.cancel()
            resetTask = Task {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                confirmed = false
            }
        }
        .motion(.morphQuick, value: confirmed)
        .onDisappear { resetTask?.cancel() }
    }
}


struct GlassActionCapsule: View {
    let title: String
    let systemImage: String
    var progress: Double? = nil
    var stage: String? = nil
    var flash: String? = nil
    var isProminent = false
    var isCollapsed = false
    var height: CGFloat = GlassMetrics.actionHeight
    let action: () -> Void

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    private var isRunning: Bool { progress != nil }

    var body: some View {
        Button(action: action) {
            GeometryReader { proxy in
                let filled = proxy.size.width * min(max(progress ?? 0, 0), 1)
                ZStack(alignment: .leading) {
                    if isRunning {
                        Rectangle()
                            .fill(Palette.accent)
                            .frame(width: filled)
                            .frame(maxHeight: .infinity)
                            .transition(.opacity)
                    }

                    label.foregroundStyle(baseInk)

                    if isRunning {
                        label
                            .foregroundStyle(Palette.onAccent)
                            .mask(alignment: .leading) {
                                Rectangle().frame(width: filled)
                            }
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .leading)
                .clipShape(Capsule())
                .motion(.smooth(duration: 0.35), value: progress)
            }
            .frame(height: height)
            .frame(minWidth: height, maxWidth: isCollapsed ? height : .infinity)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(glass, in: .capsule)
        .onHover { isHovering = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityValue(
            progress.map { Text($0, format: .percent.precision(.fractionLength(0))) } ?? Text("")
        )
    }

    @ViewBuilder
    private var label: some View {
        ZStack {
            if isCollapsed {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .transition(.blurPop)
            } else if let flash, !isRunning {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                    Text(flash)
                        .font(.system(size: 13, weight: .semibold))
                }
                .transition(AnyTransition(.blurReplace))
            } else if isRunning {
                Text(runningTitle)
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    .contentTransition(.numericText())
                    .motion(.morphQuick, value: runningTitle)
                    .transition(AnyTransition(.blurReplace))
            } else {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                }
                .transition(AnyTransition(.blurReplace))
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
    }

    private var runningTitle: String {
        if isHovering { return "Cancel" }
        let percent = (progress ?? 0).formatted(.percent.precision(.fractionLength(0)))
        guard let stage else { return percent }
        return "\(stage) \(percent)"
    }

    private var baseInk: Color {
        if !isEnabled { return isProminent ? Palette.onAccent.opacity(0.5) : Palette.disabledLabel }
        if !isRunning, flash != nil { return .white }
        if !isRunning, isProminent { return Palette.onAccent }
        return Palette.label
    }

    private var glass: Glass {
        var glass = Glass.regular
        if !isRunning {
            if flash != nil, isEnabled {
                glass = glass.tint(Palette.success)
            } else if isProminent {
                glass = glass.tint(Palette.accent.opacity(isEnabled ? 1 : 0.45))
            }
        }
        return glass.interactive(isEnabled)
    }

    private var helpText: String {
        if isRunning { return "Cancel \(title)" }
        return title
    }
}


struct KeyCap: View {
    let label: String
    var isSmall = false

    var body: some View {
        Text(label)
            .font(.system(size: isSmall ? 10.5 : 11.5, weight: .semibold, design: .rounded))
            .foregroundStyle(Palette.label)
            .padding(.horizontal, label.count > 1 ? (isSmall ? 5 : 7) : 0)
            .frame(minWidth: isSmall ? 18 : 22, minHeight: isSmall ? 18 : 22)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: isSmall ? 5 : 6, style: .continuous))
    }
}

struct KeyCaps: View {
    let tokens: [String]
    var isSmall = false

    var body: some View {
        GlassEffectContainer(spacing: 3) {
            HStack(spacing: isSmall ? 3 : 4) {
                ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                    KeyCap(label: token, isSmall: isSmall)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tokens.joined())
    }
}

struct Tag: View {
    let text: String
    var systemImage: String? = nil
    var tint: Color? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 8.5, weight: .bold))
            }
            Text(text)
                .font(.dsMicro)
        }
        .foregroundStyle(tint ?? Palette.secondaryLabel)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background((tint ?? Color.primary).opacity(tint == nil ? 0.07 : 0.14), in: Capsule())
    }
}

struct StatusDot: View {
    var color: Color = Palette.success

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}


struct EmptyStateView<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    @ViewBuilder var actions: () -> Actions

    var body: some View {
        VStack(spacing: Space.l) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Palette.secondaryLabel)
                .frame(width: 56, height: 56)
                .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .padding(.bottom, Space.xs)

            Text(title)
                .font(.dsTitle)
                .foregroundStyle(Palette.label)

            Text(message)
                .font(.dsCallout)
                .foregroundStyle(Palette.secondaryLabel)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 300)

            if Actions.self != EmptyView.self {
                GlassEffectContainer(spacing: GlassMetrics.containerSpacing) {
                    HStack(spacing: GlassMetrics.gap) {
                        actions()
                    }
                }
                .padding(.top, Space.s)
            }
        }
        .padding(Space.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(systemImage: String, title: String, message: String) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}
