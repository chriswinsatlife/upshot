import SwiftUI

struct RecordingStartFlyout: View {
    var presentedHoverMode: RecordingOutputMode?

    var body: some View {
        InterfaceFlyoutMenu {
            row(.video)
            row(.gif)
            InterfaceFlyoutDivider()
            row(.studio)
        }
        .onAppear {
            RecordingOutputModeCoordinator.shared.clearPendingMode()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Start Recording")
    }

    private func row(_ mode: RecordingOutputMode) -> some View {
        InterfaceFlyoutRow(mode.title, systemImage: mode.systemImage, keyHint: mode.keyHint) {
            RecordingOutputModeCoordinator.shared.record(mode)
        }
        .interfacePresentedControlState(presentedHoverMode == mode ? .hover : nil)
    }
}
