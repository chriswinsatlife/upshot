import AppKit
import SwiftUI

@MainActor
final class CaptureCodeFeedbackPresenter {
    static let shared = CaptureCodeFeedbackPresenter()
    private var panel: NSPanel?

    private init() {}

    func present(_ detection: CaptureCodeDetection, displayID: CGDirectDisplayID?) {
        panel?.close()
        panel = nil
        guard !detection.isEmpty else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) == displayID
        } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = NSSize(width: min(460, frame.width - 40), height: min(400, frame.height - 80))
        let panel = CaptureCodePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "Detected Codes and Links"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: CaptureCodeFeedbackView(detection: detection) { [weak panel] in panel?.close() })
        let origin = CGPoint(x: frame.midX - size.width / 2,
                             y: min(frame.minY + 166, frame.maxY - panel.frame.height - 20))
        panel.setFrameOrigin(origin)
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        panel.orderFrontRegardless()
        self.panel = panel
        NSLog("Capture code prompt presented: codes=%ld links=%ld", detection.codes.count, detection.links.count)
    }
}

private final class CaptureCodePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct CaptureCodeFeedbackView: View {
    let detection: CaptureCodeDetection
    let dismiss: () -> Void
    @State private var copied: Set<String> = []
    @State private var failure: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(detection.codes) { code in
                        VStack(alignment: .leading, spacing: 6) {
                            Label(code.title, systemImage: "qrcode.viewfinder").font(.headline)
                            Text(code.displayPayload)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            if code.payload == nil {
                                Text("Binary payload displayed as Base64.").font(.caption).foregroundStyle(.secondary)
                            }
                            Button(copied.contains(code.id) ? "Payload Copied" : "Copy Payload") { copy(code) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    ForEach(detection.links, id: \.self) { link in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(link.absoluteString)
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Open Link") { open(link) }
                                Button(copied.contains(link.absoluteString) ? "Link Copied" : "Copy Link") { copy(link) }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(2)
            }
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Dismiss", action: dismiss).keyboardShortcut(.cancelAction)
            }
        }
        .padding(16)
        .onExitCommand(perform: dismiss)
    }

    private func copy(_ code: DetectedCaptureCode) {
        let item = NSPasteboardItem()
        item.setString(code.displayPayload, forType: .string)
        if let data = code.data {
            item.setData(data, forType: NSPasteboard.PasteboardType("public.data"))
        }
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.writeObjects([item]) {
            copied.insert(code.id)
            failure = nil
            NSLog("Capture code payload copied: symbology=%@", code.symbology)
        } else {
            failure = "The payload could not be copied."
            NSLog("Capture code payload copy failed")
        }
    }

    private func copy(_ link: URL) {
        NSPasteboard.general.clearContents()
        if NSPasteboard.general.setString(link.absoluteString, forType: .string) {
            copied.insert(link.absoluteString)
            failure = nil
            NSLog("Capture detected link copied")
        } else {
            failure = "The link could not be copied."
            NSLog("Capture detected link copy failed")
        }
    }

    private func open(_ link: URL) {
        if NSWorkspace.shared.open(link) {
            failure = nil
            NSLog("Capture detected link opened after confirmation")
        } else {
            failure = "The link could not be opened."
            NSLog("Capture detected link open failed")
        }
    }
}
