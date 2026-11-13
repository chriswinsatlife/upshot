import SwiftUI

struct GlassCropBar: View {
    let aspect: CropAspectRatio
    let onAspectChange: (CropAspectRatio) -> Void
    let onReset: () -> Void
    let onCancel: () -> Void
    let onApply: () -> Void
    var resetHelp = "Reset the selection to the whole image"

    var body: some View {
        InterfacePanel(.panel) {
            HStack(spacing: Space.xxs) {
                aspectMenu

                InterfaceToolbarDivider()

                labeledButton("Reset", systemImage: "arrow.counterclockwise", action: onReset)
                    .help(resetHelp)

                labeledButton("Cancel", systemImage: "xmark", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                    .help("Cancel Crop (Esc)")

                InterfaceToolbarDivider()

                labeledButton("Crop", systemImage: "checkmark", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .help("Apply the crop (Return)")
            }
            .fixedSize()
        }
    }

    private var aspectMenu: some View {
        Menu {
            Picker("Aspect Ratio", selection: Binding(get: { aspect }, set: onAspectChange)) {
                ForEach(CropAspectRatio.allCases) { aspect in
                    Text(aspect.title).tag(aspect)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: Space.s) {
                Image(systemName: "aspectratio")
                    .font(.system(size: IconSize.flyout, weight: .medium))
                Text(aspect.title)
                    .font(.dsBodyEmphasis)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: IconSize.disclosureChevron, weight: .bold))
                    .foregroundStyle(Palette.secondaryLabel)
            }
            .foregroundStyle(Palette.label)
            .padding(.horizontal, Space.ml)
            .frame(height: AnnotationToolDock.iconButtonSize)
            .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.toolbarButton))
        .fixedSize()
        .help("Crop aspect ratio")
        .accessibilityLabel("Crop aspect ratio")
        .accessibilityValue(aspect.title)
    }

    private func labeledButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Space.s) {
                Image(systemName: systemImage)
                    .font(.system(size: IconSize.flyout, weight: .medium))
                Text(title)
                    .font(.dsBodyEmphasis)
                    .lineLimit(1)
            }
            .foregroundStyle(Palette.label)
            .padding(.horizontal, Space.ml)
            .frame(height: AnnotationToolDock.iconButtonSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(InterfaceFloatingButtonStyle(cornerRadius: Radius.toolbarButton))
        .accessibilityLabel(title)
    }
}
