import AppKit
import SwiftUI

struct StudioActionFooter: View {
    @Bindable var model: RecordingStudioModel
    var showsStatus = true

    @State private var isExportOptionsPresented = false
    @State private var isShareOptionsPresented = false
    @State private var exportFlash: String?
    @State private var shareFlash: String?
    @State private var lastJob: Job?
    @State private var expiredFailure: String?

    private enum Job {
        case export
        case share
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if showsStatus {
                status
                    .id(statusKey)
                    .transition(AnyTransition(.blurReplace))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Group {
                if let running = runningJob {
                    progressRow(running)
                        .transition(AnyTransition(.blurReplace))
                } else {
                    actionRow
                        .transition(AnyTransition(.blurReplace))
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, InspectorMetrics.horizontalPadding)
        .padding(.top, Space.ml)
        .padding(.bottom, Space.xl)
        .motion(.morphQuick, value: layoutKey)
        .motion(.morphQuick, value: statusKey)
        .task(id: statusKey) {
            guard case .failed(_, let message) = currentStatus else { return }
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

    private var actionRow: some View {
        HStack(spacing: Space.m) {
            Spacer(minLength: 0)

            if model.canShareToCloud, let link = finishedShareLink {
                Button {
                    copy(link)
                    flashShare("Copied")
                } label: {
                    Label("Copy Link Again", systemImage: "link")
                        .labelStyle(.iconOnly)
                }
                .help("Copy Link Again")
            }

            if let url = finishedExportURL {
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .labelStyle(.iconOnly)
                }
                .help("Show in Finder")
            }

            if model.canShareToCloud {
                shareButton
            }

            exportButton
        }
        .buttonStyle(.interfaceAction)
    }

    private var exportButton: some View {
        Button {
            isExportOptionsPresented = true
        } label: {
            if let exportFlash {
                Label(exportFlash, systemImage: "checkmark")
            } else {
                Label("Export", systemImage: "square.and.arrow.down")
            }
        }
        .disabled(!model.isLoaded)
        .keyboardShortcut("e", modifiers: .command)
        .popover(isPresented: $isExportOptionsPresented, arrowEdge: .top) {
            RecordingExportOptionsPopover(
                initialSettings: model.exportSettings,
                initialDeliveryOptions: model.exportDeliveryOptions,
                onConfirm: model.export(settings:)
            )
        }
    }

    private var shareButton: some View {
        Button {
            isShareOptionsPresented = true
        } label: {
            if let shareFlash {
                Label(shareFlash, systemImage: "checkmark")
            } else {
                Label("Share", systemImage: "link")
            }
        }
        .disabled(!model.isLoaded)
        .popover(isPresented: $isShareOptionsPresented, arrowEdge: .top) {
            CloudUploadOptionsPopover(
                suggestedTitle: model.projectDisplayName,
                onConfirm: model.shareToCloud
            )
        }
    }

    private func progressRow(_ running: RunningJob) -> some View {
        HStack(spacing: Space.m) {
            Text(running.stage)
                .font(.dsCaption)
                .foregroundStyle(Palette.secondaryLabel)
                .lineLimit(1)
                .fixedSize()
            ProgressView(value: min(max(running.progress, 0), 1))
                .progressViewStyle(.linear)
                .controlSize(.small)
                .tint(Palette.accent)
                .accessibilityLabel(running.stage)
            Text(running.progress, format: .percent.precision(.fractionLength(0)))
                .font(.dsNumeric)
                .foregroundStyle(Palette.secondaryLabel)
                .contentTransition(.numericText())
                .fixedSize()
            Button("Cancel") {
                switch running.job {
                case .export: model.cancelExport()
                case .share: model.cancelShare()
                }
            }
            .buttonStyle(.interfaceAction)
            .keyboardShortcut(running.job == .export ? KeyboardShortcut("e", modifiers: .command) : nil)
            .help(running.job == .export ? "Cancel Export" : "Cancel Share")
        }
    }

    @ViewBuilder
    private var status: some View {
        switch currentStatus {
        case .summary(let text):
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(Palette.secondaryLabel)
                .lineLimit(1)
        case .exported(let url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                completedLine("Saved \(url.lastPathComponent)")
            }
            .buttonStyle(.plain)
            .help("Show \(url.lastPathComponent) in Finder")
        case .shared(let link):
            if let url = URL(string: link) {
                Link(destination: url) {
                    completedLine(Self.displayLink(link))
                }
                .help("Open the share link in your browser")
            } else {
                completedLine("Link copied")
            }
        case .failed(let title, let message):
            InterfaceRow(title, detail: message, systemImage: "exclamationmark.triangle", detailIsCritical: true) {
                EmptyView()
            }
            .help(message)
        }
    }

    private func completedLine(_ text: String) -> some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: IconSize.actionButton, weight: .semibold))
                .foregroundStyle(Palette.success)
            Text(text)
                .font(.dsCaption)
                .foregroundStyle(Palette.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private enum Status {
        case summary(String)
        case exported(URL)
        case shared(String)
        case failed(title: String, message: String)
    }

    private struct RunningJob {
        let job: Job
        let stage: String
        let progress: Double
    }

    private var runningJob: RunningJob? {
        if case .exporting(let progress) = model.exportState {
            return RunningJob(job: .export, stage: "Exporting", progress: progress)
        }
        switch model.shareState {
        case .rendering(let progress):
            return RunningJob(job: .share, stage: "Rendering", progress: progress)
        case .uploading:
            let progress = model.shareItemID.flatMap { CloudUploader.shared.uploadProgress[$0] } ?? 0
            return RunningJob(job: .share, stage: "Uploading", progress: progress)
        default:
            return nil
        }
    }

    private var reportedJob: Job {
        if let lastJob { return lastJob }
        if model.exportState == .idle, model.shareState != .idle { return .share }
        return .export
    }

    private var currentStatus: Status {
        if runningJob != nil {
            return .summary(settingsSummary)
        }
        switch reportedJob {
        case .export:
            if case .finished(let url) = model.exportState { return .exported(url) }
            if case .failed(let message) = model.exportState, expiredFailure != message {
                return .failed(title: "Export failed", message: message)
            }
        case .share:
            if case .finished(let link) = model.shareState { return .shared(link) }
            if case .failed(let message) = model.shareState, expiredFailure != message {
                return .failed(title: "Share failed", message: message)
            }
        }
        return .summary(settingsSummary)
    }

    private var statusKey: String {
        switch currentStatus {
        case .summary(let text): "summary-\(text)"
        case .exported(let url): "exported-\(url.path)"
        case .shared(let link): "shared-\(link)"
        case .failed(let title, let message): "failed-\(title)-\(message)"
        }
    }

    private var layoutKey: String {
        [
            runningJob != nil,
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
