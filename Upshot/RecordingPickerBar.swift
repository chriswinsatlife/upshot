import AppKit
import AVFoundation
import Combine
import ScreenCaptureKit
import SwiftUI

@MainActor
enum RecordingPickerPresenter {
    static var shared: RecordingBarPresenter { RecordingBarPresenter.shared }
}

extension RecordingBarPresenter {
    func toggle() {
        togglePicker()
    }

    func show() {
        showPicker()
    }
}

struct RecordingPickerControls: View {
    @State private var sources = RecordingSourceCatalog.shared
    @State private var target = RecordingSourceTargetPresenter.shared
    @State private var area = RecordingAreaSelectionPresenter.shared
    @State private var cameras = UpshotStorage.isRenderingStates ? [] : RecordingDeviceCatalog.cameras()
    @AppStorage(UpshotPreferences.recordingCameraDeviceIDKey) private var cameraID = ""
    @AppStorage(UpshotPreferences.recordingMicrophoneDeviceIDKey) private var microphoneID = ""
    @AppStorage(UpshotPreferences.recordingSystemAudioKey) private var systemAudio = false
    @AppStorage(UpshotPreferences.recordingStartDelaySecondsKey) private var startDelaySeconds = 0
    @AppStorage(UpshotPreferences.recordingTeleprompterEnabledKey) private var teleprompterEnabled = false

    private static let timerOptions = [0, 1, 3, 5]

    var body: some View {
        HStack(spacing: BarMetrics.itemSpacing) {
            displaySource.disabled(CaptureCountdownPresenter.shared.isRunning)
            windowSource.disabled(CaptureCountdownPresenter.shared.isRunning || sources.isLoading)
            BarActionButton(
                id: .area,
                title: "Drag to select a region",
                systemImage: "rectangle.dashed",
                isSelected: area.isActive,
                accessibility: "Area - drag to select the region to record"
            ) {
                area.toggle()
            }
            .disabled(!canSelectSource)

            BarDivider()

            cameraPicker

            microphonePicker

            inputToggle(
                id: .systemAudio,
                title: systemAudio ? "System audio on" : "System audio off",
                isOn: systemAudio,
                onIcon: "speaker.wave.2.fill",
                offIcon: "speaker.slash",
                accessibility: systemAudio
                    ? "System audio on - click to stop capturing what you hear"
                    : "System audio off - click to capture what you hear"
            ) {
                systemAudio.toggle()
            }

            inputToggle(
                id: .teleprompter,
                title: teleprompterEnabled ? "Teleprompter on" : "Teleprompter off",
                isOn: teleprompterEnabled,
                onIcon: "text.pad.header",
                offIcon: "text.pad.header",
                accessibility: teleprompterEnabled
                    ? "Teleprompter on - click to edit the script"
                    : "Teleprompter off - click to write a script"
            ) {
                RecordingBarPresenter.shared.toggleTeleprompter()
            }

            timerMenu

            BarActionButton(
                id: .close,
                title: "Close",
                systemImage: "xmark",
                accessibility: "Close the recorder - Esc"
            ) {
                dismissPicker()
            }
        }
        .task {
            guard !UpshotStorage.isRenderingStates else { return }
            cameras = RecordingDeviceCatalog.cameras()
            await sources.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)
            .receive(on: RunLoop.main)) { _ in
            cameras = RecordingDeviceCatalog.cameras()
        }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureDevice.wasDisconnectedNotification)
            .receive(on: RunLoop.main)) { _ in
            cameras = RecordingDeviceCatalog.cameras()
        }
    }

    private var canSelectSource: Bool {
        !sources.isLoading && !sources.displays.isEmpty && !CaptureCountdownPresenter.shared.isRunning
    }

    @ViewBuilder
    private var displaySource: some View {
        if sources.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(width: BarMetrics.controlSize, height: BarMetrics.controlSize)
                .help("Finding screens and windows…")
                .accessibilityLabel("Finding screens and windows")
        } else if !UpshotStorage.isRenderingStates && (sources.errorMessage != nil || sources.displays.isEmpty) {
            Menu {
                Text(sources.errorMessage ?? "No screens are available.")
                Button("Retry") { Task { await sources.refresh() } }
                if !CGPreflightScreenCaptureAccess() {
                    Button("Open Screen Recording Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } label: {
                BarActionLabel(id: .display, title: "Recording sources unavailable - click to retry",
                               systemImage: "exclamationmark.triangle")
            }
            .menuStyle(.button)
            .buttonStyle(BarButtonStyle())
            .menuIndicator(.hidden)
            .accessibilityLabel("Recording sources unavailable - retry or open permissions")
        } else {
            BarActionButton(
                id: .display,
                title: "Point at a screen to record",
                systemImage: "menubar.rectangle",
                isSelected: target.mode == .display,
                accessibility: "Display - point at the screen to record, then click it"
            ) {
                target.toggle(.display)
            }
        }
    }

    private var windowSource: some View {
        BarActionButton(
            id: .window,
            title: "Point at a window to record",
            systemImage: "macwindow",
            isSelected: target.mode == .window,
            accessibility: "Window - point at the window to record, then click it"
        ) {
            target.toggle(.window)
        }
        .contextMenu {
            if let errorMessage = sources.errorMessage {
                Text("Could not load windows: \(errorMessage)")
            } else if sources.windows.isEmpty {
                Text("No app windows found")
            }
            ForEach(sources.windows, id: \.windowID) { window in
                Button(RecordingSourceCatalog.windowTitle(window)) {
                    target.cancel()
                    startRecording {
                        CaptureCoordinator.shared.recordWindow(window)
                    }
                }
            }
        }
    }

    private func startRecording(_ start: () -> Void) {
        RecordingBarPresenter.shared.closeTeleprompter()
        start()
    }

    private func dismissPicker() {
        RecordingBarPresenter.shared.hide()
        Task { await CameraRecordingManager.shared.stopPreview() }
    }

    private var cameraTooltip: String {
        guard !cameraID.isEmpty else { return "Camera off" }
        guard let camera = cameras.first(where: { $0.uniqueID == cameraID }) else { return "Camera unavailable" }
        return "Camera: \(camera.localizedName)"
    }

    private var cameraAccessibilityLabel: String {
        guard !cameraID.isEmpty else {
            return "Camera off - click to choose a camera"
        }
        guard let camera = cameras.first(where: { $0.uniqueID == cameraID }) else {
            return "Camera unavailable - click to choose another camera"
        }
        return "Camera on - \(camera.localizedName), click to switch"
    }

    private var microphoneTooltip: String {
        guard !microphoneID.isEmpty else { return "Microphone off" }
        guard RecordingDeviceCatalog.microphone(withID: microphoneID) != nil else {
            return "Microphone unavailable"
        }
        return "Microphone on"
    }

    private var microphoneAccessibilityLabel: String {
        guard !microphoneID.isEmpty else {
            return "Microphone off - click to choose an input"
        }
        guard let microphone = RecordingDeviceCatalog.microphone(withID: microphoneID) else {
            return "Microphone unavailable - choose another input"
        }
        return "Microphone on - \(microphone.localizedName)"
    }

    private var cameraPicker: some View {
        Menu {
            Button {
                cameraID = ""
                Task { await CameraRecordingManager.shared.stopPreview() }
            } label: {
                menuSelectionLabel("Off", isSelected: cameraID.isEmpty)
            }

            Divider()

            if cameras.isEmpty {
                Text("No cameras available")
            }

            ForEach(cameras, id: \.uniqueID) { device in
                Button {
                    selectCamera(device.uniqueID)
                } label: {
                    menuSelectionLabel(device.localizedName, isSelected: cameraID == device.uniqueID)
                }
            }
        } label: {
            BarActionLabel(
                id: .camera,
                title: cameraTooltip,
                systemImage: cameraID.isEmpty ? "video.slash" : "video.fill",
                tint: cameraID.isEmpty ? BarMetrics.inactiveTint : BarMetrics.activeTint
            )
        }
        .menuStyle(.button)
        .buttonStyle(BarButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel(cameraAccessibilityLabel)
    }

    private var microphonePicker: some View {
        Menu {
            Button {
                microphoneID = ""
            } label: {
                menuSelectionLabel("Off", isSelected: microphoneID.isEmpty)
            }

            Divider()

            ForEach(RecordingDeviceCatalog.microphones(), id: \.uniqueID) { device in
                Button {
                    selectMicrophone(device.uniqueID)
                } label: {
                    menuSelectionLabel(
                        device.localizedName,
                        isSelected: microphoneID == device.uniqueID
                    )
                }
            }
        } label: {
            BarActionLabel(
                id: .microphone,
                title: microphoneTooltip,
                systemImage: microphoneID.isEmpty ? "mic.slash" : "mic.fill",
                tint: microphoneID.isEmpty ? BarMetrics.inactiveTint : BarMetrics.activeTint
            )
        }
        .menuStyle(.button)
        .buttonStyle(BarButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel(microphoneAccessibilityLabel)
    }

    private var timerMenu: some View {
        Menu {
            ForEach(Self.timerOptions, id: \.self) { seconds in
                Button {
                    startDelaySeconds = seconds
                } label: {
                    menuSelectionLabel(timerLabel(seconds), isSelected: startDelaySeconds == seconds)
                }
            }
        } label: {
            BarActionLabel(
                id: .timer,
                title: timerTooltip,
                systemImage: "timer",
                tint: startDelaySeconds == 0 ? BarMetrics.inactiveTint : BarMetrics.activeTint
            )
        }
        .menuStyle(.button)
        .buttonStyle(BarButtonStyle())
        .menuIndicator(.hidden)
        .accessibilityLabel(timerAccessibilityLabel)
    }

    private func timerLabel(_ seconds: Int) -> String {
        seconds == 0 ? "None" : "\(seconds) second\(seconds == 1 ? "" : "s")"
    }

    private var timerTooltip: String {
        startDelaySeconds == 0 ? "Timer off" : "Timer \(startDelaySeconds)s"
    }

    private var timerAccessibilityLabel: String {
        startDelaySeconds == 0
            ? "Timer off - click to add a countdown before recording starts"
            : "Timer: \(timerLabel(startDelaySeconds)) before recording starts"
    }

    @ViewBuilder
    private func menuSelectionLabel(_ title: String, isSelected: Bool) -> some View {
        if isSelected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }

    private func selectCamera(_ deviceID: String?) {
        guard let deviceID else { return }
        Task { @MainActor in
            let authorized = await RecordingInputAuthorization.ensureAccess(for: .camera)
            cameraID = authorized ? deviceID : ""
            if authorized {
                await warmCameraPreview()
            }
        }
    }

    private func warmCameraPreview() async {
        guard !cameraID.isEmpty else { return }
        let displayID = ActiveDisplayResolver.activeDisplayID(preferPointer: false)
        await CameraRecordingManager.shared.startPreview(deviceID: cameraID, displayID: displayID)
    }

    private func selectMicrophone(_ deviceID: String?) {
        guard let deviceID else { return }
        Task { @MainActor in
            microphoneID = await RecordingInputAuthorization.ensureAccess(for: .microphone) ? deviceID : ""
        }
    }

    private func inputToggle(
        id: BarTooltipID,
        title: String,
        isOn: Bool,
        onIcon: String,
        offIcon: String,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        BarActionButton(
            id: id,
            title: title,
            systemImage: isOn ? onIcon : offIcon,
            tint: isOn ? BarMetrics.activeTint : BarMetrics.inactiveTint,
            accessibility: accessibility,
            action: action
        )
    }
}
