import SwiftUI

struct CaptureHistoryView: View {
    @Bindable var model: CaptureHistoryModel
    @State private var history = ScreenshotHistoryStore.shared
    @State private var projects = RecordingProjectStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if let error = model.errorMessage {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
            captures
            HStack {
                Text("← → Select · Tab Filter · Return Restore · Esc Close")
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(model.visibleItems.count) captures")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        .onChange(of: history.items) { _, _ in model.refresh() }
        .onChange(of: projects.projects) { _, _ in model.refresh() }
        .accessibilityLabel("Capture History")
    }

    private var header: some View {
        HStack(spacing: 16) {
            Text("Capture History")
                .font(.headline)
            Picker("Capture Type", selection: $model.filter) {
                ForEach(CaptureHistoryFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 540)
            Spacer(minLength: 0)
            Button("Restore", systemImage: "arrow.uturn.backward") {
                model.restoreSelection()
            }
            .disabled(model.selectedItem == nil)
            Button {
                CaptureHistoryPresenter.shared.dismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close Capture History")
            .help("Close Capture History (Escape)")
        }
    }

    private var captures: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(model.visibleItems) { item in
                        CaptureHistoryCard(item: item, isSelected: model.selectedID == item.id) {
                            model.selectedID = item.id
                        }
                        .id(item.id)
                    }
                }
                .padding(3)
            }
            .overlay {
                if model.visibleItems.isEmpty {
                    if model.isLoading {
                        ProgressView("Loading Captures…")
                    } else {
                        ContentUnavailableView("No Captures", systemImage: "clock.arrow.circlepath", description: Text("Captures appear here after a screenshot or recording."))
                    }
                }
            }
            .onChange(of: model.selectedID) { _, id in
                if let id { proxy.scrollTo(id, anchor: .center) }
            }
        }
        .frame(maxHeight: .infinity)
    }
}

private struct CaptureHistoryCard: View {
    let item: CaptureLibraryItem
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                CaptureLibraryThumbnail(item: item)
                    .frame(height: 108)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Text(item.name)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(CaptureHistoryFilter.kindTitle(for: item))
                    Spacer(minLength: 0)
                    Text(item.createdAt, style: .date)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .padding(8)
            .frame(width: 188)
            .background(isSelected ? Color.accentColor.opacity(0.14) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(item.name), \(CaptureHistoryFilter.kindTitle(for: item))")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .help("Select \(item.name), then choose Restore")
    }
}
