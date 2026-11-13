
import AppKit
import SwiftUI

struct StudioActionFooter: View {
    @Bindable var model: RecordingStudioModel
    var showsStatus = true

    @State private var isExportOptionsPresented = false
    @State private var isShareOptionsPresented = false
    @State private var exportFlash: String?
    @State private var shareFlash: String?
    @State private var lastJob: Job = .export
    @State private var expiredFailure: String?
    @Namespace private var glass

    private enum Job {
        case export
        case share
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsStatus {
                status
                    .id(statusKey)
                    .transition(AnyTransition(.blurReplace))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            GlassEffectContainer(spacing: GlassMetrics.containerSpacing) {
                HStack(spacing: GlassMetrics.gap) {
                    if model.canShareToCloud {
                        shareCapsule
                        if let link = finishedShareLink, !isShareRunning, !isExportRunning {
                            GlassIconButton(
                                systemImage: "link",
                                help: "Copy Link Again",
                                size: GlassMetrics.actionHeight
                            ) {
                                copy(link)
                                flashShare("Copied")
                            }
                            .glassEffectID("copyLink", in: glass)
                        }
                    }

                    exportCapsule

                    if let url = finishedExportURL, !isExportRunning, !isShareRunning {
                        GlassIconButton(
                            systemImage: "folder",
                            help: "Show in Finder",
                            size: GlassMetrics.actionHeight
                        ) {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .glassEffectID("reveal", in: glass)
                    }
                }
            }
        }
        .padding(.horizontal, InspectorMetrics.horizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .motion(.morph, value: layoutKey)
        .motion(.morphQuick, value: statusKey)
        .task(id: statusKey) {
            guard case .failed(let message) = currentStatus else { return }
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            expiredFailure = message
        }
        .onChange(of: model.exportState) { _, state in
            lastJob = .export
            expiredFailure = nil
            if case .finished = state { flashExport("Exported") }
        }
        .onChange(of: model.shareState) { _, state in
            lastJob = .share
            expiredFailure = nil
            if case .finished = state { flashShare("Link Copied") }
        }
    }


    private var exportCapsule: some View {
        GlassActionCapsule(
            title: "Export",
            systemImage: "arrow.down.circle",
            progress: exportProgress,
            flash: exportFlash,
            isProminent: true,
            isCollapsed: isShareRunning
        ) {
            if isExportRunning {
                model.cancelExport()
            } else {
                isExportOptionsPresented = true
            }
        }
        .disabled(!model.isLoaded || isShareRunning)
        .keyboardShortcut("e", modifiers: .command)
        .glassEffectID("export", in: glass)
        .popover(isPresented: $isExportOptionsPresented, arrowEdge: .top) {
            RecordingExportOptionsPopover(
                initialSettings: model.exportSettings,
                initialDeliveryOptions: model.exportDeliveryOptions,
                onConfirm: model.export(settings:)
            )
        }
    }

    private var shareCapsule: some View {
        GlassActionCapsule(
            title: "Share",
            systemImage: "link",
            progress: shareProgress?.progress,
            stage: shareProgress?.stage,
            flash: shareFlash,
            isCollapsed: isExportRunning
        ) {
            if isShareRunning {
                model.cancelShare()
            } else {
                isShareOptionsPresented = true
            }
        }
        .disabled(!model.isLoaded || isExportRunning)
        .glassEffectID("share", in: glass)
        .popover(isPresented: $isShareOptionsPresented, arrowEdge: .top) {
            CloudUploadOptionsPopover(
                suggestedTitle: model.projectDisplayName,
                onConfirm: model.shareToCloud
            )
        }
    }


    @ViewBuilder
    private var status: some View {
        switch currentStatus {
        case .summary(let text):
            statusLine(text, systemImage: nil, tint: nil)
        case .exported(let url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                statusLine("Saved \(url.lastPathComponent)", systemImage: "checkmark.circle.fill", tint: nil)
            }
            .buttonStyle(.plain)
            .help("Show \(url.lastPathComponent) in Finder")
        case .shared(let link):
            if let url = URL(string: link) {
                Link(destination: url) {
                    statusLine(Self.displayLink(link), systemImage: "checkmark.circle.fill", tint: nil)
                }
                .help("Open the share link in your browser")
            } else {
                statusLine("Link copied", systemImage: "checkmark.circle.fill", tint: nil)
            }
        case .failed(let message):
            statusLine(message, systemImage: "exclamationmark.triangle.fill", tint: .orange)
                .help(message)
        }
    }

    private func statusLine(_ text: String, systemImage: String?, tint: Color?) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(tint ?? .secondary)
            }
            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private enum Status {
        case summary(String)
        case exported(URL)
        case shared(String)
        case failed(String)
    }

    private var currentStatus: Status {
        if isExportRunning || isShareRunning {
            return .summary(settingsSummary)
        }
        switch lastJob {
        case .export:
            if case .finished(let url) = model.exportState { return .exported(url) }
            if case .failed(let message) = model.exportState, expiredFailure != "Export failed: \(message)" {
                return .failed("Export failed: \(message)")
            }
        case .share:
            if case .finished(let link) = model.shareState { return .shared(link) }
            if case .failed(let message) = model.shareState, expiredFailure != "Share failed: \(message)" {
                return .failed("Share failed: \(message)")
            }
        }
        return .summary(settingsSummary)
    }

    private var statusKey: String {
        switch currentStatus {
        case .summary(let text): "summary-\(text)"
        case .exported(let url): "exported-\(url.path)"
        case .shared(let link): "shared-\(link)"
        case .failed(let message): "failed-\(message)"
        }
    }

    private var layoutKey: String {
        [
            isExportRunning, isShareRunning,
            exportFlash != nil, shareFlash != nil,
            finishedExportURL != nil, finishedShareLink != nil
        ]
        .map { $0 ? "1" : "0" }
        .joined()
    }

    private var settingsSummary: String {
        let settings = model.exportSettings
        let resolution = settings.resolution == .original ? "Full size" : settings.resolution.rawValue
        return [
            settings.effectiveContainer.rawValue,
            resolution,
            settings.effectiveFrameRate.rawValue
        ].joined(separator: " · ")
    }


    private var isExportRunning: Bool {
        if case .exporting = model.exportState { return true }
        return false
    }

    private var isShareRunning: Bool {
        model.shareState.isBusy
    }

    private var exportProgress: Double? {
        if case .exporting(let progress) = model.exportState { return progress }
        return nil
    }

    private var shareProgress: (stage: String, progress: Double)? {
        switch model.shareState {
        case .rendering(let progress):
            return ("Rendering", progress)
        case .uploading:
            let progress = model.shareItemID.flatMap { CloudUploader.shared.uploadProgress[$0] } ?? 0
            return ("Uploading", progress)
        default:
            return nil
        }
    }

    private var finishedExportURL: URL? {
        if case .finished(let url) = model.exportState { return url }
        return nil
    }

    private var finishedShareLink: String? {
        if case .finished(let link) = model.shareState { return link }
        return nil
    }

    private func flashExport(_ text: String) {
        exportFlash = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard exportFlash == text else { return }
            exportFlash = nil
        }
    }

    private func flashShare(_ text: String) {
        shareFlash = text
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.4))
            guard shareFlash == text else { return }
            shareFlash = nil
        }
    }

    private func copy(_ link: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    private static func displayLink(_ link: String) -> String {
        guard let url = URL(string: link), let host = url.host() else { return link }
        return host + url.path()
    }
}

struct StudioProgressRing: View {
    let progress: Double

    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 2)
            Circle()
                .trim(from: 0, to: max(0.03, min(1, progress)))
                .stroke(Palette.highlight, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.easeOut(duration: 0.15), value: progress)
    }
}
