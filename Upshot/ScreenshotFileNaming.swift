import Foundation

enum ScreenshotFileNaming {
    static func fileName(date: Date = Date(), extension pathExtension: String = "png") -> String {
        "Upshot_\(timestampFormatter.string(from: date)).\(pathExtension)"
    }

    static func applyingRetinaSuffix(to fileName: String, outputScale: CGFloat) -> String {
        guard UpshotPreferences.screenshotRetinaSuffix, outputScale >= 1.5 else { return fileName }
        let url = URL(fileURLWithPath: fileName)
        let stem = url.deletingPathExtension().lastPathComponent
        guard !stem.hasSuffix("@2x") else { return fileName }
        let result = "\(stem)@2x.\(url.pathExtension)"
        NSLog("Screenshot output: Retina filename suffix applied")
        return result
    }

    static func uniqueURL(fileName: String, in directory: URL) -> URL {
        let initialURL = directory.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: initialURL.path) else { return initialURL }
        let stem = initialURL.deletingPathExtension().lastPathComponent
        let hasSuffix = stem.hasSuffix("@2x")
        let base = hasSuffix ? String(stem.dropLast(3)) : stem
        for counter in 2...10_000 {
            let candidate = directory.appendingPathComponent("\(base)-\(counter)\(hasSuffix ? "@2x" : "").\(initialURL.pathExtension)")
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return directory.appendingPathComponent("\(base)-\(UUID().uuidString)\(hasSuffix ? "@2x" : "").\(initialURL.pathExtension)")
    }

    static func historyFileName(for sourceURL: URL) -> String {
        sourceURL.lastPathComponent
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        return formatter
    }()
}
