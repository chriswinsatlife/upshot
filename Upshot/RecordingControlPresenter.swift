import AppKit
import SwiftUI

@MainActor
enum RecordingControlPresenter {
    static var shared: RecordingBarPresenter { RecordingBarPresenter.shared }
}

extension RecordingBarPresenter {
    func show(displayID: CGDirectDisplayID?) {
        showRecording(displayID: displayID)
    }
}

struct RecordingSessionControls: View {
    @State private var manager = ScreenRecordingManager.shared
    @State private var pen = RecordingPenPresenter.shared

    private var isPaused: Bool {
        manager.state == .paused
    }

    private var isSettling: Bool {
        manager.state == .starting || manager.state == .finishing
    }

    var body: some View {
        HStack(spacing: Space.xxs) {
            HStack(spacing: 0) {
                InterfaceToolbarButton(
                    "Stop and save",
                    systemImage: "stop.circle",
                    labelPlacement: .hidden,
                    tint: Palette.record
                ) {
                    manager.stopRecording()
                }
                .disabled(isSettling)
                .accessibilityLabel("Stop and save the recording")

                elapsed
            }

            InterfaceToolbarDivider()

            InterfaceToolbarButton(
                isPaused ? "Resume recording" : "Pause recording",
                systemImage: isPaused ? "play.circle" : "pause.circle",
                labelPlacement: .hidden
            ) {
                if isPaused {
                    manager.resumeRecording()
                } else {
                    manager.pauseRecording()
                }
            }
            .disabled(isSettling)

            InterfaceToolbarButton(
                pen.isEnabled ? "Stop drawing" : "Draw on recording",
                systemImage: "pencil.tip.crop.circle",
                isSelected: pen.isEnabled,
                labelPlacement: .hidden
            ) {
                RecordingPenPresenter.toggleLivePen()
            }
            .disabled(manager.state != .recording)

            InterfaceToolbarButton(
                "Clear pen annotations",
                systemImage: "eraser",
                labelPlacement: .hidden
            ) {
                RecordingPenPresenter.clearLivePen()
            }
            .disabled(manager.state != .recording || !pen.hasStrokes)

            InterfaceToolbarButton(
                "Start over",
                systemImage: "arrow.counterclockwise",
                labelPlacement: .hidden
            ) {
                manager.restartRecording()
            }
            .disabled(isSettling)
            .accessibilityLabel("Restart - discard what's recorded and start again")

            InterfaceToolbarButton(
                "Discard recording",
                systemImage: "trash",
                labelPlacement: .hidden
            ) {
                manager.deleteRecording()
            }
            .disabled(manager.state == .starting)
            .accessibilityLabel("Discard - delete this recording without saving")
        }
        .fixedSize()
    }

    private var elapsed: some View {
        Text(manager.formattedElapsedTime)
            .font(.dsBodyEmphasis.monospacedDigit())
            .foregroundStyle(isPaused || isSettling ? Palette.secondaryLabel : Palette.record)
            .padding(.trailing, Space.m)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                isPaused
                    ? "Recording paused at \(manager.formattedElapsedTime)"
                    : "Recording, \(manager.formattedElapsedTime) elapsed"
            )
    }
}
