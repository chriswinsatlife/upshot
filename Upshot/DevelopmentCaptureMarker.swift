import Foundation

nonisolated enum DevelopmentCaptureMarker {
    static let tagName = "Upshot Dev"
    static let developmentBundleIdentifier = "co.chrisyork.upshot.dev"

    static var isDevelopmentBuild: Bool {
        Bundle.main.bundleIdentifier == developmentBundleIdentifier
    }

    static func mark(_ url: URL) {
        guard isDevelopmentBuild else { return }
        let existingTags = (try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames) ?? []
        guard !existingTags.contains(tagName) else { return }
        var values = URLResourceValues()
        values.tagNames = existingTags + [tagName]
        var taggedURL = url
        do {
            try taggedURL.setResourceValues(values)
            AppLog.event("verification", "development_capture_tagged", fields: ["file": url.lastPathComponent, "tag": tagName])
        } catch {
            AppLog.event("verification", "development_capture_tag_failed", fields: ["file": url.lastPathComponent, "error": AppLog.error(error)])
        }
    }
}
