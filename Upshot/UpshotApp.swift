import SwiftUI
import UniformTypeIdentifiers
import UserNotifications
import Carbon

@main
enum UpshotMain {
    static func main() {
        AppLog.installExceptionHandler()
        if StateRenderer.isRequested { StateRenderer.run() }
        if AutomationCommandLine.isRequested { AutomationCommandLine.run() }
        if AgentRelay.isRequested {
            AgentRelay.run()
        }
        CrashDiagnostics.shared.start()
        UpshotApp.main()
    }
}

struct UpshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.openWindow) var openWindow
    @AppStorage(UpshotPreferences.showMenuBarIconKey) private var showMenuBarIcon = true

    var body: some Scene {
        let _ = configurePreviewPresentation()

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
        } label: {
            RecordingMenuBarLabel()
        }

        Window("Upshot Library", id: "CAPTURE_LIBRARY") {
            CaptureLibraryWindow()
        }
        .defaultSize(width: 1180, height: 760)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Show Library") { CaptureLibraryModel.shared.show() }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { SettingsWindowController.show(tab: .general) }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }

        WindowGroup("Upshot Annotate", id: "ANNOTATION_EDITOR", for: URL.self) { value in
            AnnotationEditorWindow(url: value)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 760)

        WindowGroup("Upshot Recording Editor", id: "VIDEO_EDITOR", for: URL.self) { value in
            RecordingStudioWindow(url: value)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1360, height: 860)
    }

    @MainActor
    private func configurePreviewPresentation() {
        CaptureLibraryModel.shared.installOpener { [openWindow] in
            openWindow(id: "CAPTURE_LIBRARY")
        }
        CaptureShelfPresenter.shared.onAnnotate = { [openWindow] url in
            openWindow(id: "ANNOTATION_EDITOR", value: url)
        }
        let openVideoEditor: (URL) -> Void = { [openWindow] url in
            let editorURL = ScreenshotHistoryStore.shared.editorURL(for: url)
            openWindow(id: "VIDEO_EDITOR", value: editorURL)
            if StudioProjectRegistry.shared.hasLoadedEditor(for: editorURL) {
                CaptureShelf.shared.dismissVideo(for: editorURL)
            }
        }
        CaptureShelfPresenter.shared.onEditVideo = openVideoEditor
        RecordingProjectOpener.shared.openHandler = openVideoEditor

        CaptureCoordinator.shared.onShowPreview = { [openWindow] url, displayID, source in
            CaptureShelfPresenter.shared.onAnnotate = { url in
                openWindow(id: "ANNOTATION_EDITOR", value: url)
            }
            CaptureShelfPresenter.shared.onEditVideo = openVideoEditor

            let historyURL = ScreenshotHistoryStore.shared.importScreenshot(from: url, source: source)
            CaptureShelf.shared.add(url: historyURL)

            if AfterCaptureActions.isEnabled(.showOverlay, for: .screenshot) {
                CaptureShelfPresenter.shared.show(displayID: displayID)
            }

            return historyURL
        }

        appDelegate.onOpenFiles = { [openWindow] urls in
            for url in urls where UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true {
                let historyURL = ScreenshotHistoryStore.shared.importScreenshot(from: url)
                openWindow(id: "ANNOTATION_EDITOR", value: historyURL)
            }
        }

        ScreenRecordingManager.shared.onFinishRecording = { session, displayID in
            Task { @MainActor in
                let historyURL = await ScreenshotHistoryStore.shared.importRecordingSession(session)
                RecordingProjectStore.shared.reload()
                CaptureShelf.shared.addVideo(url: historyURL)
                if AfterCaptureActions.isEnabled(.showOverlay, for: .recording) {
                    CaptureShelfPresenter.shared.show(displayID: displayID)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let updaterManager = UpdaterManager.shared
    private var openedFilesAtLaunch = false

    private var pendingOpenURLs: [URL] = []
    var onOpenFiles: (([URL]) -> Void)? {
        didSet {
            guard let onOpenFiles, !pendingOpenURLs.isEmpty else { return }
            let urls = pendingOpenURLs
            pendingOpenURLs = []
            application(NSApp, open: urls)
        }
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = RecordingExportNotificationDelegate.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        if RecordingExportBenchmark.runIfRequested() { return }
        #endif
        HotkeyManager.shared.registerHotkeys()
        AutomationConfiguration.shared.start()
        updaterManager.start()
        AgentServer.shared.updateForPreference()
        RecordingRecoveryCoordinator.recoverInterruptedRecordings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            CaptureLibraryIndex.shared.start()
        }
        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchReason = launchEvent?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue
        let launchedInBackground = launchReason == keyAELaunchedAsLogInItem
            || launchReason == keyAELaunchedAsServiceItem
            || CommandLine.arguments.contains(AgentSocket.launchedByAgentArgument)
        DispatchQueue.main.async { [weak self] in
            guard let self, !launchedInBackground, !self.openedFilesAtLaunch else { return }
            CaptureLibraryModel.shared.show()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        openedFilesAtLaunch = true
        guard let onOpenFiles else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        let automationURLs = urls.filter { $0.scheme?.lowercased() == "upshot" }
        for url in automationURLs { AutomationURLRouter.handle(url) }
        let urls = urls.filter { $0.scheme?.lowercased() != "upshot" }
        guard !urls.isEmpty else { return }
        onOpenFiles(urls)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let appWindowVisible = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        AppLog.event("application", "application_reopen", fields: ["appWindowVisible": String(describing: appWindowVisible), "hasVisibleWindows": String(describing: hasVisibleWindows), "library": String(describing: appWindowVisible ? "skipped" : "shown")])
        guard !appWindowVisible else { return false }
        CaptureLibraryModel.shared.show()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.event("application", "process_terminating")
        AppLog.shared.flush()
        AutomationConfiguration.shared.stop()
        AgentServer.shared.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        StudioProjectRegistry.shared.flushDrafts()
        let unsavedProjectCount = StudioProjectRegistry.shared.unsavedProjectCount
        let unsavedCount = CaptureShelf.shared.unsavedItems.count
        if ScreenRecordingManager.shared.isActive {
            NSApp.activate(ignoringOtherApps: true)

            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "A screen recording is still in progress"
            alert.informativeText = unsavedCount > 0
                ? "Upshot will finish and save the recording before quitting. You also have \(unsavedCount) unsaved capture\(unsavedCount == 1 ? "" : "s") that will be discarded."
                : "Upshot will finish and save the recording before quitting. This can take a moment for a long recording."
            alert.addButton(withTitle: "Cancel")
            alert.addButton(withTitle: "Finish Recording and Quit")

            guard alert.runModal() == .alertSecondButtonReturn else {
                return .terminateCancel
            }

            ScreenRecordingManager.shared.finishForTermination { session in
                Task { @MainActor in
                    if let session {
                        _ = await ScreenshotHistoryStore.shared.importRecordingSession(session)
                    }
                    sender.reply(toApplicationShouldTerminate: true)
                }
            }
            return .terminateLater
        }

        guard unsavedCount > 0 else { return .terminateNow }

        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = unsavedCount == 1
            ? "You have 1 unsaved capture"
            : "You have \(unsavedCount) unsaved captures"
        var informativeText = """
        These captures haven't been saved to your Mac and will be lost if you quit. \
        Turn on Auto Save in Settings to keep every capture automatically.
        """
        if unsavedProjectCount > 0 {
            informativeText += """
            \n\n\(unsavedProjectCount) recording project\(unsavedProjectCount == 1 ? " has" : "s have") \
            unsaved edits. Those are kept and restored the next time you open them.
            """
        }
        alert.informativeText = informativeText

        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Quit Anyway")

        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
