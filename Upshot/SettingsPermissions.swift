import AppKit
import AVFoundation
import SwiftUI

@MainActor
@Observable
final class SettingsPermissions {
    enum Kind: CaseIterable, Identifiable {
        case screenRecording
        case microphone
        case camera

        var id: Self { self }

        var title: String {
            switch self {
            case .screenRecording: "Screen Recording"
            case .microphone: "Microphone"
            case .camera: "Camera"
            }
        }

        var detail: String {
            switch self {
            case .screenRecording: "Required for screenshots and recordings."
            case .microphone: "Narrate recordings and transcribe captions."
            case .camera: "Add a camera bubble to recordings."
            }
        }

        var systemImage: String {
            switch self {
            case .screenRecording: "rectangle.dashed.badge.record"
            case .microphone: "mic.fill"
            case .camera: "video.fill"
            }
        }

        var isRequired: Bool { self == .screenRecording }

        fileprivate var settingsAnchor: String {
            switch self {
            case .screenRecording: "Privacy_ScreenCapture"
            case .microphone: "Privacy_Microphone"
            case .camera: "Privacy_Camera"
            }
        }
    }

    private(set) var granted: Set<Kind> = []
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var watchers = 0

    func isGranted(_ kind: Kind) -> Bool { granted.contains(kind) }

    var missingRequired: Kind? {
        Kind.allCases.first { $0.isRequired && !granted.contains($0) }
    }

    func beginWatching() {
        guard !UpshotStorage.isRenderingStates else { granted = StateRenderer.scenario.contains("denied") ? [] : Set(Kind.allCases); return }
        watchers += 1
        refresh()
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                self?.refresh()
            }
        }
    }

    func endWatching() {
        watchers = max(0, watchers - 1)
        guard watchers == 0 else { return }
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() {
        var next: Set<Kind> = []
        if CGPreflightScreenCaptureAccess() { next.insert(.screenRecording) }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .authorized { next.insert(.microphone) }
        if AVCaptureDevice.authorizationStatus(for: .video) == .authorized { next.insert(.camera) }
        if next != granted { granted = next }
    }

    func request(_ kind: Kind) {
        switch kind {
        case .screenRecording:
            if !CGRequestScreenCaptureAccess() { openSettings(for: kind) }
        case .microphone, .camera:
            let mediaType: AVMediaType = kind == .microphone ? .audio : .video
            if AVCaptureDevice.authorizationStatus(for: mediaType) == .notDetermined {
                Task {
                    _ = await AVCaptureDevice.requestAccess(for: mediaType)
                    refresh()
                }
            } else {
                openSettings(for: kind)
            }
        }
    }

    private func openSettings(for kind: Kind) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(kind.settingsAnchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}

struct SettingsPermissionRow: View {
    let kind: SettingsPermissions.Kind
    let permissions: SettingsPermissions

    var body: some View {
        let granted = permissions.isGranted(kind)
        HStack(spacing: 12) {
            Image(systemName: kind.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(granted ? Palette.label : (kind.isRequired ? Palette.warning : Palette.secondaryLabel))
                .frame(width: 22)

            InterfaceRowLabel(kind.title, detail: kind.detail)

            Spacer(minLength: 8)

            ZStack(alignment: .trailing) {
                if granted {
                    Label("Allowed", systemImage: "checkmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .transition(.blurPop)
                } else {
                    InterfaceActionButton("Allow") {
                        permissions.request(kind)
                    }
                    .transition(.blurPop)
                }
            }
        }
        .motion(value: granted)
    }
}

struct SettingsStatusFooter: View {
    let permissions: SettingsPermissions

    var body: some View {
        let missing = permissions.missingRequired
        HStack(alignment: .center, spacing: 9) {
            StatusDot(color: missing == nil ? Palette.success : Palette.warning)

            VStack(alignment: .leading, spacing: 1) {
                Text(missing == nil ? "Ready to capture" : "Needs attention")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Palette.label)
                Text(missing.map { "Allow \($0.title)" } ?? SettingsStatusFooter.versionString)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            if let missing { permissions.request(missing) }
        }
        .motion(value: missing)
    }

    static let versionString: String = {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "Version \(version) (\(build))"
    }()
}
