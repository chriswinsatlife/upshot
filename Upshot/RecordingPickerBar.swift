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
    @State private var countdown = CaptureCountdownPresenter.shared
    @State private var cameras = UpshotStorage.isRenderingStates ? [] : RecordingDeviceCatalog.cameras()
    @AppStorage(UpshotPreferences.recordingCameraDeviceIDKey) private var cameraID = ""
    @AppStorage(UpshotPreferences.recordingMicrophoneDeviceIDKey) private var microphoneID = ""
    @AppStorage(UpshotPreferences.recordingSystemAudioKey) private var systemAudio = false
    @AppStorage(UpshotPreferences.recordingStartDelaySecondsKey) private var startDelaySeconds = 0
    @AppStorage(UpshotPreferences.recordingTeleprompterEnabledKey) private var teleprompterEnabled = false

    private static let timerOptions = [0, 1, 3, 5]

    var body: some View {
        HStack(spacing: Space.xxs) {
            displaySource.disabled(countdown.isRunning)
            windowSource.disabled(countdown.isRunning || sources.isLoading)
            InterfaceToolbarButton("Area", systemImage: "rectangle.dashed", isSelected: area.isActive) {
                area.toggle()
            }
            .disabled(!canSelectSource)
            .accessibilityLabel("Area - drag to select the region to record")

            InterfaceToolbarDivider()

            cameraPicker
            microphonePicker

            InterfaceToolbarButton(
                "System Audio",
                systemImage: systemAudio ? "speaker.wave.2" : "speaker.slash",
                isSelected: systemAudio
            ) {
                systemAudio.toggle()
            }
            .accessibilityLabel(systemAudio
                ? "System audio on - click to stop capturing what you hear"
                : "System audio off - click to capture what you hear")

            InterfaceToolbarButton(
                "Teleprompter",
                systemImage: "text.pad.header",
                isSelected: teleprompterEnabled
            ) {
                RecordingBarPresenter.shared.toggleTeleprompter()
            }
            .accessibilityLabel(teleprompterEnabled
                ? "Teleprompter on - click to edit the script"
                : "Teleprompter off - click to write a script")

            timerMenu

            InterfaceToolbarDivider()

            InterfaceToolbarButton("Close", systemImage: "xmark") {
                dismissPicker()
            }
            .accessibilityLabel("Close the recorder - Esc")
        }
        .fixedSize()
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
        !sources.isLoading && !sources.displays.isEmpty && !countdown.isRunning
    }

    @ViewBuilder
    private var displaySource: some View {
        if sources.isLoading {
            VStack(spacing: InterfaceMetrics.toolbarIconToLabelSpacing) {
                ProgressView()
                    .controlSize(.small)
                    .frame(height: 20)
                Text("Display")
                    .font(.dsToolbarLabel)
                    .foregroundStyle(Palette.disabledLabel)
                    .fixedSize()
            }
            .frame(minWidth: InterfaceMetrics.toolbarButtonMinimumWidth, minHeight: InterfaceMetrics.toolbarButtonHeight)
            .help("Finding screens and windows…")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Finding screens and windows")
        } else if !UpshotStorage.isRenderingStates && (sources.errorMessage != nil || sources.displays.isEmpty) {
            RecordingBarMenuButton(
                title: "Display",
                systemImage: "exclamationmark.triangle",
                accessibility: "Recording sources unavailable - retry or open permissions"
            ) {
                Text(sources.errorMessage ?? "No screens are available.")
                Button("Retry") { Task { await sources.refresh() } }
                if !CGPreflightScreenCaptureAccess() {
                    Button("Open Screen Recording Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
        } else {
            InterfaceToolbarButton("Display", systemImage: "menubar.rectangle", isSelected: target.mode == .display) {
                target.toggle(.display)
            }
            .accessibilityLabel("Display - point at the screen to record, then click it")
        }
    }

    private var windowSource: some View {
        InterfaceToolbarButton("Window", systemImage: "macwindow", isSelected: target.mode == .window) {
            target.toggle(.window)
        }
        .accessibilityLabel("Window - point at the window to record, then click it")
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

    private var cameraAccessibilityLabel: String {
        guard !cameraID.isEmpty else {
            return "Camera off - click to choose a camera"
        }
        guard let camera = cameras.first(where: { $0.uniqueID == cameraID }) else {
            return "Camera unavailable - click to choose another camera"
        }
        return "Camera on - \(camera.localizedName), click to switch"
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
        RecordingBarMenuButton(
            title: "Camera",
            systemImage: cameraID.isEmpty ? "video.slash" : "video",
            isSelected: !cameraID.isEmpty,
            accessibility: cameraAccessibilityLabel
        ) {
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
        }
    }

    private var microphonePicker: some View {
        RecordingBarMenuButton(
            title: "Microphone",
            systemImage: microphoneID.isEmpty ? "mic.slash" : "mic",
            isSelected: !microphoneID.isEmpty,
            accessibility: microphoneAccessibilityLabel
        ) {
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
        }
    }

    private var timerMenu: some View {
        RecordingBarMenuButton(
            title: startDelaySeconds == 0 ? "Timer" : "\(startDelaySeconds)s",
            systemImage: "timer",
            isSelected: startDelaySeconds != 0,
            accessibility: timerAccessibilityLabel
        ) {
            ForEach(Self.timerOptions, id: \.self) { seconds in
                Button {
                    startDelaySeconds = seconds
                } label: {
                    menuSelectionLabel(timerLabel(seconds), isSelected: startDelaySeconds == seconds)
                }
            }
        }
    }

    private func timerLabel(_ seconds: Int) -> String {
        seconds == 0 ? "None" : "\(seconds) second\(seconds == 1 ? "" : "s")"
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
}
