import SwiftUI

struct AllInOneCaptureToolbar: View {
    static let singleRowMinimumWidth: CGFloat = 820
    static let bottomInset: CGFloat = 28

    let selector: AreaCaptureSelection
    let stacksSizeFields: Bool

    var body: some View {
        VStack(spacing: Space.m) {
            if let status = selector.status {
                InterfaceToast(status, systemImage: "exclamationmark.circle", tone: .failure)
                    .transition(.opacity)
            }
            if stacksSizeFields {
                VStack(spacing: Space.m) {
                    sizeFields
                    modes
                }
            } else {
                HStack(alignment: .bottom, spacing: Space.l) {
                    modes
                    sizeFields
                }
            }
        }
        .fixedSize()
    }

    private var modes: some View {
        VStack(alignment: .trailing, spacing: Space.m) {
            if selector.mode == .recording {
                recordingOutputs
                    .transition(.opacity)
            }
            modePanel
        }
    }

    private var recordingOutputs: some View {
        InterfaceFlyoutMenu {
            ForEach(RecordingOutputMode.allCases, id: \.self) { output in
                if output == .studio { InterfaceFlyoutDivider() }
                InterfaceFlyoutRow(output.title, systemImage: output.systemImage, keyHint: output.keyHint) {
                    selector.chooseRecordingOutput(output)
                }
            }
        }
        .disabled(!selector.canRecordSelection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recording Type")
    }

    private var modePanel: some View {
        InterfacePanel {
            HStack(spacing: Space.xxs) {
                InterfaceToolbarButton("Cancel", systemImage: "xmark", labelPlacement: .hidden, action: selector.cancel)
                    .keyboardShortcut(.cancelAction)
                InterfaceToolbarDivider()
                    .padding(.horizontal, Space.xs)
                ForEach(AllInOneCaptureMode.toolbarCaptureModes) { mode in
                    button(mode)
                }
                InterfaceToolbarDivider()
                    .padding(.horizontal, Space.xs)
                button(.text)
                InterfaceToolbarDivider()
                    .padding(.horizontal, Space.xs)
                button(.recording)
            }
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Capture Mode")
    }

    private func button(_ mode: AllInOneCaptureMode) -> some View {
        InterfaceToolbarButton(mode.title, systemImage: mode.symbol, isSelected: isSelected(mode)) {
            selector.chooseMode(mode)
        }
        .disabled(mode.isCaptureAction && !selector.canArmCaptureActions)
        .help(mode.toolbarHelp)
    }

    private func isSelected(_ mode: AllInOneCaptureMode) -> Bool {
        switch mode {
        case .timer: selector.selfTimerArmed
        case .text: selector.textRecognitionArmed
        case .area: selector.mode == .area || selector.mode == .previousArea
        default: selector.mode == mode
        }
    }

    @ViewBuilder
    private var sizeFields: some View {
        if selector.showsSelectionSize, let size = selector.selectionPixelSize {
            InterfaceSizeFieldsPill(
                width: Binding(get: { Int(size.width) }, set: { selector.setSelectionPixelSize(width: $0) }),
                height: Binding(get: { Int(size.height) }, set: { selector.setSelectionPixelSize(height: $0) }),
                aspectSystemImage: selector.aspect == nil ? "crop" : "aspectratio"
            ) {
                Picker("Aspect Ratio", selection: Binding(get: { selector.aspect }, set: { selector.setAspect($0) })) {
                    Text("Freeform").tag(RecordingAreaAspect?.none)
                    Divider()
                    ForEach(RecordingAreaAspect.allPresets, id: \.self) { aspect in
                        Text(aspect.title).tag(Optional(aspect))
                    }
                }
                .pickerStyle(.inline)
            }
            .onSubmit { selector.restoreKeyboardFocus() }
            .transition(.opacity)
        }
    }
}

struct AreaCaptureInstructionHint: View {
    let selector: AreaCaptureSelection

    var body: some View {
        InterfacePanel(.pill, padding: 0) {
            Text(selector.instruction)
                .font(.dsBodyEmphasis)
                .foregroundStyle(Palette.label)
                .lineLimit(1)
                .padding(.horizontal, Space.xl)
                .frame(height: InterfaceMetrics.toastMinimumHeight)
        }
        .fixedSize()
    }
}
