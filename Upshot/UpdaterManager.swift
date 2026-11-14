import AppKit
import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterManager: NSObject, ObservableObject {
    static let shared = UpdaterManager()

    private let controller: SPUStandardUpdaterController?
    private let availability = UpdateAvailabilityDelegate()
    private var lastInformationCheck: Date?

    @Published var canCheckForUpdates = false

    @Published private(set) var availableUpdateVersion: String?

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? true }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    static let isEnabled = (Bundle.main.object(forInfoDictionaryKey: "UpshotSparkleUpdatesEnabled") as? String) == "YES"

    private override init() {
        controller = UpshotStorage.isRenderingStates || !Self.isEnabled ? nil : SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: availability,
            userDriverDelegate: nil
        )
        super.init()
        availability.onChange = { [weak self] version in self?.availableUpdateVersion = version }

        controller?.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func start() {
        guard let controller else {
            AppLog.event("application", "sparkle_updater_disabled", fields: ["reason": UpshotStorage.isRenderingStates ? "rendering_states" : "source_build"])
            return
        }
        controller.startUpdater()
        AppLog.event("application", "sparkle_updater_started", fields: ["feed": Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "none"])
        checkForUpdateInformation()
    }

    func checkForUpdateInformation() {
        guard let controller else { return }
        if let lastInformationCheck, Date().timeIntervalSince(lastInformationCheck) < 3600 { return }
        guard !controller.updater.sessionInProgress else { return }
        lastInformationCheck = Date()
        controller.updater.checkForUpdateInformation()
    }

    func checkForUpdates() {
        guard let controller else { return }
        NSApp.setActivationPolicy(AppActivationPolicy.windowPolicy)
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}

private final class UpdateAvailabilityDelegate: NSObject, SPUUpdaterDelegate {
    @MainActor var onChange: ((String?) -> Void)?

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { onChange?(version) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        MainActor.assumeIsolated { onChange?(nil) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        MainActor.assumeIsolated { onChange?(nil) }
    }
}
