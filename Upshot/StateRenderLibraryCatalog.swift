import AppKit
import SwiftUI

enum StateRenderLibraryCatalog {
    private struct LibraryFixture {
        var items: [CaptureLibraryItem]
        var analyses: [String: CaptureAnalysis] = [:]
        var unsortedExistingCount = 0
        var readingCount = 0
    }

    static func states(fixtures: StateRenderFixtures) -> [StateRenderDefinition] {
        let variants = [
            "grid", "list", "empty", "screenshots-empty", "recordings-empty",
            "search", "search-empty", "inspector", "no-selection", "multi-selection",
            "screenshots", "recordings", "categories", "category", "app", "scope-empty",
            "selected-analyzed", "selected-recording", "selected-shared", "list-selected",
            "sort-offer", "indexing", "busy", "categories-collapsed", "update-available"
        ]
        return variants.map { variant in
            StateRenderDefinition("library-\(variant)", source: "CaptureLibraryView", marker: "struct CaptureLibraryView",
                                  size: CGSize(width: 1280, height: 850)) {
                AnyView(makeView(variant: variant, fixtures: fixtures))
            }
        }
    }

    private static func makeView(variant: String, fixtures: StateRenderFixtures) -> CaptureLibraryView {
        let defaults = UpshotStorage.defaults
        let model = CaptureLibraryModel.shared
        let analyzed = ["categories", "category", "scope-empty", "selected-analyzed", "search", "sort-offer", "indexing", "categories-collapsed", "app"].contains(variant)
        let fixture = variant.hasSuffix("empty") && !variant.hasPrefix("search") && variant != "scope-empty"
            ? LibraryFixture(items: [])
            : libraryFixture(items: fixtures.items, analyzed: analyzed, variant: variant)
        defaults.set(analyzed, forKey: UpshotPreferences.libraryAnalyzeCapturesKey)
        defaults.set(variant == "sort-offer" ? false : true, forKey: UpshotPreferences.librarySortExistingKey)
        defaults.set(false, forKey: UpshotPreferences.librarySortOfferDismissedKey)
        defaults.set(variant != "categories-collapsed", forKey: "captureLibrary.categoriesExpanded")
        defaults.set(true, forKey: "captureLibrary.appsExpanded")
        defaults.set(variant.hasPrefix("list") ? "list" : "grid", forKey: "captureLibrary.layout")
        let showsInspector = variant.hasPrefix("inspector") || variant.hasPrefix("selected") || variant == "no-selection" || ["multi-selection", "categories", "sort-offer", "indexing", "list-selected", "search"].contains(variant)
        defaults.set(showsInspector, forKey: "captureLibrary.inspectorVisible")
        CaptureLibraryIndex.shared.installRenderAnalyses(fixture.analyses, unsortedExistingCount: fixture.unsortedExistingCount, readingCount: fixture.readingCount)
        model.installRenderItems(fixture.items)
        model.operationTitle = variant == "busy" ? "Exporting 2 captures…" : nil
        let screenshot = fixture.items.first { !$0.isVideo && $0.source != nil }
        switch variant {
        case "screenshots", "screenshots-empty": model.scope = .kind(.screenshots)
        case "recordings", "recordings-empty": model.scope = .kind(.recordings)
        case "category": model.scope = .category(.design)
        case "scope-empty": model.scope = .category(.receipt)
        case "app": model.scope = .app("com.apple.Safari")
        case "search": model.searchText = "Release"
        case "search-empty": model.searchText = "No matching capture"
        default: break
        }
        switch variant {
        case "inspector", "selected-analyzed", "categories", "sort-offer", "indexing", "list-selected", "search":
            if let screenshot { model.selection = [screenshot.id] }
        case "selected-recording":
            if let recording = fixture.items.first(where: { $0.session != nil }) { model.selection = [recording.id] }
        case "selected-shared":
            if let shared = fixture.items.first(where: { $0.cloudURL != nil }) { model.selection = [shared.id] }
        case "multi-selection", "busy":
            model.selection = Set(fixture.items.prefix(2).map(\.id))
        default: break
        }
        return CaptureLibraryView(presentedUpdateVersion: variant == "update-available" ? "2.4" : nil)
    }

    private static func libraryFixture(items: [CaptureLibraryItem], analyzed: Bool, variant: String) -> LibraryFixture {
        let sources: [String: CaptureSource] = [
            "Release Overview": CaptureSource(bundleIdentifier: "com.apple.Safari", appName: "Safari", windowTitle: "Release Overview – Upshot Workspace"),
            "Capture Workflow": CaptureSource(bundleIdentifier: "com.apple.Preview", appName: "Preview", windowTitle: "Capture Workflow.pdf"),
            "Design Review": CaptureSource(bundleIdentifier: "com.apple.Safari", appName: "Safari", windowTitle: "Design Review"),
            "Project Notes": CaptureSource(bundleIdentifier: "com.apple.Notes", appName: "Notes", windowTitle: "Project Notes")
        ]
        let categories: [String: CaptureCategory] = [
            "Release Overview": .website, "Capture Workflow": .document, "Design Review": .design, "Project Notes": .document
        ]
        var fixture = LibraryFixture(items: [])
        var sharedAssigned = false
        for item in items {
            let baseName = (item.name as NSString).deletingPathExtension
            let source = item.isVideo ? item.source : sources[baseName] ?? item.source
            let isShared = variant == "selected-shared" && !sharedAssigned && !item.isVideo && sources[baseName] != nil
            if isShared { sharedAssigned = true }
            let fixtureItem = CaptureLibraryItem(
                id: item.id, historyIDs: item.historyIDs, name: item.name, fileURL: item.fileURL, session: item.session,
                createdAt: item.createdAt, modifiedAt: item.modifiedAt, pixelWidth: item.pixelWidth, pixelHeight: item.pixelHeight,
                duration: item.duration, isVideo: item.isVideo, hasEdits: item.hasEdits || isShared, hasDraft: item.hasDraft || isShared,
                cloudURL: isShared ? "https://captures.example.com/release-overview" : item.cloudURL, source: source, thumbnailKey: item.thumbnailKey
            )
            fixture.items.append(fixtureItem)
            guard analyzed else { continue }
            let category = item.isVideo ? CaptureCategory.media : categories[baseName] ?? .other
            fixture.analyses[item.id] = CaptureAnalysis(
                id: item.id,
                fingerprint: item.thumbnailKey,
                lines: item.isVideo ? CaptureTextLines() : textLines(title: baseName),
                transcript: item.isVideo ? "This walkthrough shows how a capture moves from the selection to the shared link." : nil,
                category: category,
                title: item.isVideo ? "Capture walkthrough" : "\(baseName) workspace",
                keywords: item.isVideo ? ["walkthrough", "capture"] : ["workspace", "review", "release"],
                classifier: .rules
            )
        }
        if variant == "sort-offer" { fixture.unsortedExistingCount = 1_284 }
        if variant == "indexing", let first = fixture.items.first(where: { !$0.isVideo && $0.source != nil }) {
            fixture.readingCount = 3
            fixture.analyses[first.id] = nil
        }
        return fixture
    }

    private static func textLines(title: String) -> CaptureTextLines {
        CaptureTextLines([
            CaptureTextLine(text: "UPSHOT / WORKSPACE", box: CGRect(x: 0.172, y: 0.124, width: 0.15, height: 0.024)),
            CaptureTextLine(text: title, box: CGRect(x: 0.102, y: 0.244, width: 0.28, height: 0.062)),
            CaptureTextLine(text: "Capture, annotate, and share a clear view of the work.", box: CGRect(x: 0.103, y: 0.326, width: 0.41, height: 0.03)),
            CaptureTextLine(text: "Screenshots", box: CGRect(x: 0.119, y: 0.446, width: 0.11, height: 0.035)),
            CaptureTextLine(text: "Recordings", box: CGRect(x: 0.392, y: 0.446, width: 0.1, height: 0.035)),
            CaptureTextLine(text: "Review", box: CGRect(x: 0.666, y: 0.446, width: 0.065, height: 0.035)),
            CaptureTextLine(text: "Ready for review", box: CGRect(x: 0.103, y: 0.735, width: 0.14, height: 0.034)),
            CaptureTextLine(text: "Every capture keeps its context.", box: CGRect(x: 0.103, y: 0.79, width: 0.21, height: 0.028))
        ])
    }
}
