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
            NSLog("Pinned screenshot outcome=failed reason=imageUnavailable")
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
        NSLog("Pinned screenshot outcome=opened roundedCorners=%@ shadow=%@ border=%@", UpshotPreferences.pinnedScreenshotRoundedCorners.description, UpshotPreferences.pinnedScreenshotShadow.description, UpshotPreferences.pinnedScreenshotBorder.description)
    }

    private func close(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.contentView = nil
        panels.remove(panel)
        if panels.isEmpty, let appearanceObserver {
            NotificationCenter.default.removeObserver(appearanceObserver)
            self.appearanceObserver = nil
        }
        NSLog("Pinned screenshot outcome=closed remaining=%d", panels.count)
    }

    private func observeAppearance() {
        guard appearanceObserver == nil else { return }
        appearance = PinnedScreenshotAppearance()
        appearanceObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
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
        NSLog("Pinned screenshot appearance roundedCorners=%@ shadow=%@ border=%@ panels=%d", updated.roundedCorners.description, updated.shadow.description, updated.border.description, panels.count)
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

private struct PinnedScreenshotView: View {
    let image: NSImage
    let url: URL
    let onClose: () -> Void

    @State private var isHovered = false
    @State private var didCopy = false
    @AppStorage(UpshotPreferences.pinnedScreenshotRoundedCornersKey) private var roundedCorners = true
    @AppStorage(UpshotPreferences.pinnedScreenshotBorderKey) private var border = true

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: roundedCorners ? 10 : 0, style: .continuous)
    }

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(.white.opacity(border ? 0.25 : 0), lineWidth: 1)
            }
            .overlay(alignment: .top) {
                if isHovered {
                    toolbar
                        .padding(8)
                        .transition(.opacity.combined(with: .move(edge: .top)))
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
    }

    private var toolbar: some View {
        HStack(spacing: 6) {
            toolbarButton(systemImage: "xmark", help: "Close pin", action: onClose)

            Spacer(minLength: 0)

            toolbarButton(
                systemImage: didCopy ? "checkmark" : "doc.on.doc",
                help: "Copy to clipboard",
                action: copy
            )
            toolbarButton(systemImage: "square.and.arrow.down", help: "Save…", action: save)
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
        .glassEffect(.regular, in: .capsule)
        .environment(\.colorScheme, .dark)
    }

    private func toolbarButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace.downUp))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
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
            print("Failed to copy pinned screenshot: \(error)")
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
                print("Failed to save pinned screenshot: \(error)")
            }
        }
    }
}
