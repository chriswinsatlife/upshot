import AppKit

@objc(UpshotApplication)
class UpshotApplication: NSApplication {
    override func reportException(_ exception: NSException) {
        AppLog.captureException(exception, event: "appkit_exception")
    }
}
