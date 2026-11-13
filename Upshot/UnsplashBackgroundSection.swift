import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class UnsplashBrowser {
    static let shared = UnsplashBrowser()

    var query = ""
    private(set) var photos: [UnsplashPhoto] = []
    private(set) var hasMore = false
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var downloadingID: String?

    private(set) var keyRevision = 0

    private var loadedQuery: String?
    private var page = 0
    private var loadTask: Task<Void, Never>?

    var hasKey: Bool {
        _ = keyRevision
        return UnsplashClient.accessKey != nil
    }

    static var directory: URL {
        AnnotationWallpaperStore.wallpapersDirectory.appendingPathComponent("Unsplash", isDirectory: true)
    }

    func loadIfNeeded() {
        guard hasKey, loadedQuery == nil, !isLoading else { return }
        submit()
    }

    func submit() {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard hasKey, query != loadedQuery || errorMessage != nil else { return }
        loadTask?.cancel()
        loadedQuery = query
        photos = []
        page = 0
        load()
    }

    func loadMore() {
        guard hasMore, !isLoading else { return }
        load()
    }

    func saveKey(_ key: String) {
        let key = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        UpshotStorage.defaults.set(key, forKey: UnsplashClient.userKeyDefaultsKey)
        keyRevision += 1
        loadedQuery = nil
        errorMessage = nil
        loadIfNeeded()
    }

    func download(_ photo: UnsplashPhoto) async -> URL? {
        guard downloadingID == nil else { return nil }
        downloadingID = photo.id
        defer { downloadingID = nil }
        do {
            errorMessage = nil
            return try await UnsplashClient.download(photo, to: Self.directory)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func load() {
        let query = loadedQuery ?? ""
        let nextPage = page + 1
        isLoading = true
        errorMessage = nil
        loadTask = Task {
            do {
                let result = try await UnsplashClient.photos(query: query, page: nextPage)
                guard !Task.isCancelled else { return }
                let known = Set(photos.map(\.id))
                photos += result.photos.filter { !known.contains($0.id) }
                hasMore = result.hasMore
                page = nextPage
            } catch {
                guard !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                if (error as? UnsplashClient.ClientError) == .invalidKey { loadedQuery = nil }
            }
            isLoading = false
        }
    }
}

struct UnsplashBackgroundSection: View {

    let selectedURL: URL?
    let onSelect: (URL) -> Void

    @State private var browser = UnsplashBrowser.shared
    @State private var keyDraft = ""
    private let columns = Array(repeating: GridItem(.flexible(), spacing: Space.m, alignment: .top), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            HStack(spacing: Space.m) {
                InterfaceSectionHeader("Unsplash")
                Spacer(minLength: 0)
                Link(destination: UnsplashClient.unsplashURL) {
                    HStack(spacing: Space.xxs) {
                        Text("Photos from Unsplash")
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: IconSize.disclosureChevron, weight: .semibold))
                    }
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                }
                .buttonStyle(.plain)
            }

            if browser.hasKey {
                searchField
                results
            } else {
                keyForm
            }

            if let errorMessage = browser.errorMessage {
                Text(errorMessage)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.destructiveLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { browser.loadIfNeeded() }
    }

    private var searchField: some View {
        HStack(spacing: Space.s) {
            InterfaceSidebarSearchField(prompt: "Search photos", text: $browser.query) {
                browser.submit()
            }
            if browser.isLoading {
                ProgressView().controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if !browser.photos.isEmpty {
            LazyVGrid(columns: columns, spacing: Space.m) {
                ForEach(browser.photos) { photo in
                    UnsplashPhotoTile(
                        photo: photo,
                        isSelected: isSelected(photo),
                        isDownloading: browser.downloadingID == photo.id,
                        isEnabled: browser.downloadingID == nil
                    ) {
                        Task {
                            if let url = await browser.download(photo) { onSelect(url) }
                        }
                    }
                }
            }
            if browser.hasMore {
                Button(browser.isLoading ? "Loading…" : "Show More") { browser.loadMore() }
                    .buttonStyle(.interfaceAction)
                    .disabled(browser.isLoading)
            }
        } else if !browser.isLoading, browser.errorMessage == nil {
            Text("No photos found.")
                .font(.dsCaption)
                .foregroundStyle(Palette.secondaryLabel)
        }
    }

    private var keyForm: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                HStack(spacing: 0) {
                    TextField("", text: $keyDraft, prompt: Text("Unsplash Access Key"))
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.dsBody)
                        .onSubmit { browser.saveKey(keyDraft) }
                        .accessibilityLabel("Unsplash Access Key")
                }
                .interfaceFieldChrome()
                Button("Save") { browser.saveKey(keyDraft) }
                    .buttonStyle(.interfaceAction)
                    .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Link(destination: UnsplashClient.developersURL) {
                Text("This build has no Unsplash key. Create a free app on Unsplash and paste its Access Key.")
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .buttonStyle(.plain)
        }
    }

    private func isSelected(_ photo: UnsplashPhoto) -> Bool {
        guard let selectedURL else { return false }
        return selectedURL.standardizedFileURL.deletingLastPathComponent().path
            == UnsplashBrowser.directory.standardizedFileURL.path
            && selectedURL.lastPathComponent.hasSuffix("(\(photo.id)).jpg")
    }
}

private struct UnsplashPhotoTile: View {
    let photo: UnsplashPhoto
    let isSelected: Bool
    let isDownloading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            InspectorTile(
                title: "Photo by \(photo.user.name) on Unsplash",
                aspectRatio: 1.35,
                isSelected: isSelected,
                action: action
            ) {

                Rectangle()
                    .fill(placeholder)
                    .overlay {
                        AsyncImage(url: photo.urls.small) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            Color.clear
                        }
                    }
                    .overlay {
                        if isDownloading {
                            Rectangle().fill(.black.opacity(0.3))
                            ProgressView().controlSize(.small)
                        }
                    }
                    .clipped()
            }
            .disabled(!isEnabled && !isDownloading)

            Link(destination: photo.photographerURL) {
                Text(photo.user.name)
                    .font(.dsCaption)
                    .foregroundStyle(Palette.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Space.xxs)
            .help("\(photo.user.name) on Unsplash")
        }
    }

    private var placeholder: Color {
        guard let hex = photo.color?.trimmingCharacters(in: CharacterSet(charactersIn: "#")),
              hex.count == 6, let value = Int(hex, radix: 16) else { return Palette.controlFill }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
