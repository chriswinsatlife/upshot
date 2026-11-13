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
        HStack(spacing: BarMetrics.itemSpacing) {
            elapsed

            BarDivider()

            BarActionButton(
                id: .pauseResume,
                title: isPaused ? "Resume recording" : "Pause recording",
                systemImage: isPaused ? "play.fill" : "pause.fill"
            ) {
                if isPaused {
                    manager.resumeRecording()
                } else {
                    manager.pauseRecording()
                }
            }
            .disabled(isSettling)

            BarActionButton(
                id: .pen,
                title: pen.isEnabled ? "Stop drawing" : "Draw on recording",
                systemImage: "pencil.tip.crop.circle",
                isSelected: pen.isEnabled
            ) {
                RecordingPenPresenter.toggleLivePen()
            }
            .disabled(manager.state != .recording)

            BarActionButton(
                id: .clearPen,
                title: "Clear pen annotations",
                systemImage: "eraser"
            ) {
                RecordingPenPresenter.clearLivePen()
            }
            .disabled(manager.state != .recording || !pen.hasStrokes)

            BarActionButton(
                id: .restart,
                title: "Start over",
                systemImage: "arrow.counterclockwise",
                accessibility: "Restart - discard what's recorded and start again"
            ) {
                manager.restartRecording()
            }
            .disabled(isSettling)

            BarActionButton(
                id: .stop,
                title: "Stop and save",
                systemImage: "stop.fill",
                tint: BarMetrics.recordTint,
                accessibility: "Stop and save the recording"
            ) {
                manager.stopRecording()
            }
            .disabled(isSettling)

            BarActionButton(
                id: .discard,
                title: "Discard recording",
                systemImage: "trash.fill",
                accessibility: "Discard - delete this recording without saving"
            ) {
                manager.deleteRecording()
            }
            .disabled(manager.state == .starting)
        }
    }

    private var elapsed: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(BarMetrics.recordTint)
                .frame(width: 8, height: 8)
                .opacity(isPaused ? 0.35 : 1)

            Text(manager.formattedElapsedTime)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(BarMetrics.activeTint)
                .frame(minWidth: 56, alignment: .leading)
        }
        .padding(.leading, 8)
        .padding(.trailing, 2)
        .frame(height: BarMetrics.controlSize)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isPaused
                ? "Recording paused at \(manager.formattedElapsedTime)"
                : "Recording, \(manager.formattedElapsedTime) elapsed"
        )
    }
}
