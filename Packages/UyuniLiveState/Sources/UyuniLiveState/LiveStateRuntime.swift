import AppKit

public enum LiveStateRuntime {
    @MainActor
    public static func runIfRequested(arguments: [String] = CommandLine.arguments,
                                      application makeApplication: @MainActor () -> any LiveStateApplication) {
        guard let request = LiveStateLaunchRequest(arguments: arguments) else { return }
        run(request, application: makeApplication)
    }

    @MainActor
    public static func run(_ request: LiveStateLaunchRequest, application makeApplication: @MainActor () -> any LiveStateApplication) -> Never {
        switch request {
        case .invalid: break
        case .listLiveStates, .presentLiveState: LiveStatePrivateBundle.enter()
        }
        LiveStateLog.event("live_state_run_started", ["request": String(describing: request), "arguments": Array(CommandLine.arguments.dropFirst()), "bundle": Bundle.main.bundlePath])
        if case .invalid(let reason) = request {
            LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
            LiveStateLog.event("live_state_run_finished", ["exitStatus": 2, "reason": reason])
            exit(2)
        }
        let application = NSApplication.shared
        let initialPolicy = application.activationPolicy()
        if initialPolicy != .prohibited { _ = application.setActivationPolicy(.prohibited) }
        LiveStateLog.event("activation_policy_set", ["initialPolicy": initialPolicy.rawValue, "policy": application.activationPolicy().rawValue])
        guard application.activationPolicy() == .prohibited else {
            let reason = "The activation policy could not be set to prohibited."
            LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
            LiveStateLog.event("live_state_run_finished", ["exitStatus": 1, "reason": reason])
            exit(1)
        }
        let missingGuards = LiveStateWindowPlacement.installWindowLevelGuards() + LiveStateInteractionGuards.install()
        guard missingGuards.isEmpty else {
            let reason = "The window level and interaction guards could not be installed for \(missingGuards.joined(separator: ", "))."
            LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
            LiveStateLog.event("live_state_run_finished", ["exitStatus": 1, "reason": reason])
            exit(1)
        }
        let session = LiveStateSession(application: makeApplication(), request: request)
        session.start()
        application.run()
        exit(1)
    }
}
