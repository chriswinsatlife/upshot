import AppKit

@main
struct AppKitExceptionVerification {
    @MainActor static func main() {
        AppLog.installExceptionHandler()
        let application = ExceptionVerificationApplication.shared
        precondition(application is ExceptionVerificationApplication)
        _ = application.setActivationPolicy(.prohibited)
        precondition(application.activationPolicy() == .prohibited)
        for index in 0..<225 {
            AppLog.event("verification", "appkit_callback_breadcrumb", fields: ["index": String(index)])
            precondition(AppLog.shared.flush())
        }
        guard let event = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, subtype: 291, data1: 0, data2: 0) else { fatalError("Event construction failed") }
        application.postEvent(event, atStart: false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { exit(2) }
        application.run()
        exit(3)
    }
}

final class ExceptionVerificationApplication: UpshotApplication {
    override func sendEvent(_ event: NSEvent) {
        if event.type == .applicationDefined, event.subtype.rawValue == 291 {
            NSException(name: .invalidArgumentException, reason: "Upshot logging verification exception", userInfo: nil).raise()
            return
        }
        super.sendEvent(event)
    }

    override func reportException(_ exception: NSException) {
        super.reportException(exception)
        guard let text = try? String(contentsOf: AppLog.shared.crashFileURL, encoding: .utf8),
              text.contains("event=appkit_exception "), text.contains("breadcrumb_count=\"200\""),
              text.contains("name=\"NSInvalidArgumentException\""), text.contains("sendEvent"),
              activationPolicy() == .prohibited, windows.isEmpty else { exit(4) }
        print("appkit_exception_verification outcome=verified callback=sendEvent handler=reportException breadcrumbs=200 windows=0 activation=prohibited")
        exit(0)
    }
}
