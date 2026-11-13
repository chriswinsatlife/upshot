import AppKit
import SwiftUI

@MainActor
final class PinnedScreenshotPresenter {
    static let shared = PinnedScreenshotPresenter()

    private var panels: Set<NSPanel> = []
    private var appearanceObserver: NSObjectProtocol?
    private var appearance = PinnedScreenshotAppearance()

    private init() {}

    func pin(url: URL) {
        guard let image = ScreenshotImageLoader.downsampledImage(at: url, maxPixelSize: 1600) else {
            AppLog.event("quick_access", "pinned_screenshot", fields: ["outcome": "failed", "reason": "imageUnavailable"])
            return
        }

        observeAppearance()

        let contentSize = displaySize(forPixelSize: image.size)
        let panel = PinnedPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .resizable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = UpshotPreferences.pinnedScreenshotShadow
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentAspectRatio = contentSize
        panel.minSize = NSSize(width: 80, height: 80)

        panel.contentView = NSHostingView(
            rootView: PinnedScreenshotView(
                image: image,
                url: url,
                onClose: { [weak self, weak panel] in
                    guard let panel else { return }
                    self?.close(panel)
                }
            )
        )

        panel.setFrameOrigin(cascadedOrigin(for: contentSize))
        panel.orderFrontRegardless()
        panels.insert(panel)
        AppLog.event("quick_access", "pinned_screenshot", fields: ["border": String(describing: UpshotPreferences.pinnedScreenshotBorder.description), "outcome": "opened", "roundedCorners": String(describing: UpshotPreferences.pinnedScreenshotRoundedCorners.description), "shadow": String(describing: UpshotPreferences.pinnedScreenshotShadow.description)])
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        panels.remove(panel)
        if panels.isEmpty, let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
            self.appearanceObserver = nil
        }
        AppLog.event("quick_access", "pinned_screenshot", fields: ["outcome": "closed", "remaining": String(describing: panels.count)])
    }

    private func observeAppearance() {
        guard appearanceObserver == nil else { return }
        appearance = PinnedScreenshotAppearance()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UpshotStorage.defaults,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAppearance() }
        }
    }

    private func refreshAppearance() {
        let updated = PinnedScreenshotAppearance()
        guard updated != appearance else { return }
        appearance = updated
        for panel in panels {
            panel.hasShadow = updated.shadow
            panel.invalidateShadow()
        }
        AppLog.event("quick_access", "pinned_screenshot_appearance", fields: ["border": String(describing: updated.border.description), "panels": String(describing: panels.count), "roundedCorners": String(describing: updated.roundedCorners.description), "shadow": String(describing: updated.shadow.description)])
    }

    private func displaySize(forPixelSize pixelSize: CGSize) -> NSSize {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        var width = pixelSize.width / scale
        var height = pixelSize.height / scale
        guard width > 0, height > 0 else { return NSSize(width: 320, height: 240) }

        let longest = max(width, height)
        let maxLongest: CGFloat = 560
        let minLongest: CGFloat = 160
        let target = min(max(longest, minLongest), maxLongest)
        let factor = target / longest
        width *= factor
        height *= factor
        return NSSize(width: width.rounded(), height: height.rounded())
    }

    private func cascadedOrigin(for size: NSSize) -> CGPoint {
        let visible = NSScreen.main?.visibleFrame ?? CGRect(x: 100, y: 100, width: 800, height: 600)
        let offset = CGFloat(panels.count % 8) * 28
        return CGPoint(
            x: visible.midX - size.width / 2 + offset,
            y: visible.midY - size.height / 2 - offset
        )
    }
}

private struct PinnedScreenshotAppearance: Equatable {
    let roundedCorners = UpshotPreferences.pinnedScreenshotRoundedCorners
    let shadow = UpshotPreferences.pinnedScreenshotShadow
    let border = UpshotPreferences.pinnedScreenshotBorder
}

private final class PinnedPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

struct PinnedScreenshotView: View {
    let image: NSImage
    let url: URL
    let onClose: () -> Void

    @State private var isHovered = UpshotStorage.isRenderingStates && ["hover", "copied"].contains { StateRenderer.scenario.contains($0) }
    @State private var didCopy = UpshotStorage.isRenderingStates && StateRenderer.scenario.contains("copied")
    @AppStorage(UpshotPreferences.pinnedScreenshotRoundedCornersKey) private var roundedCorners = true
    @AppStorage(UpshotPreferences.pinnedScreenshotBorderKey) private var border = true

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: roundedCorners ? Radius.nested(inner: Radius.panel, padding: Space.s) : 0, style: .continuous)
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay {
                shape
                    .strokeBorder(Palette.floatingStroke, lineWidth: 1)
                    .opacity(border ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .overlay(alignment: .top) {
                if isHovered {
                    controls
                        .padding(Space.s)
                        .transition(.opacity)
                }
            }
            .contentShape(shape)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.15)) {
                    isHovered = hovering
                }
            }
            .contextMenu {
                Button("Copy") { copy() }
                Button("Copy Text from Image") { copyText() }
                Button("Save…") { save() }
                Divider()
                Button("Close Pin") { onClose() }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Pinned Screenshot")
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 0) {
                closePanel
                Spacer(minLength: Space.m)
                actionPanel
            }
            HStack(alignment: .top, spacing: 0) {
                closePanel
                Spacer(minLength: 0)
            }
            Color.clear
                .frame(width: 0, height: 0)
        }
    }

    private var closePanel: some View {
        InterfacePanel {
            InterfaceToolbarButton("Close Pin", systemImage: "xmark", labelPlacement: .hidden, action: onClose)
        }
        .fixedSize()
    }

    private var actionPanel: some View {
        InterfacePanel {
            HStack(spacing: Space.xxs) {
                InterfaceToolbarButton(
                    didCopy ? "Copied" : "Copy",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc",
                    labelPlacement: .hidden,
                    tint: didCopy ? Palette.success : nil,
                    action: copy
                )
                InterfaceToolbarButton("Save…", systemImage: "square.and.arrow.down", labelPlacement: .hidden, action: save)
            }
        }
        .fixedSize()
    }

    private func copy() {
        do {
            try ScreenshotFileActions.copyPNGToClipboard(from: url)
            withAnimation(.morphQuickIfAllowed) { didCopy = true }
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                withAnimation(.morphQuickIfAllowed) { didCopy = false }
            }
        } catch {
            AppLog.event("capture", "pinned_screenshot_copy_failed", fields: ["error": AppLog.error(error)])
        }
    }

    private func copyText() {
        let url = url
        Task {
            await CaptureTextActions.copyText(at: url)
        }
    }

    private func save() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [ScreenshotFileActions.exportContentType]
        panel.nameFieldStringValue = ScreenshotFileActions.exportFileName(for: url)
        panel.canCreateDirectories = true
        panel.title = "Save Screenshot"
        panel.begin { response in
            guard response == .OK, let destURL = panel.url else { return }
            do {
                try ScreenshotFileActions.save(from: url, to: destURL)
            } catch {
                AppLog.event("capture", "pinned_screenshot_save_failed", fields: ["error": AppLog.error(error)])
            }
        }
    }
}
