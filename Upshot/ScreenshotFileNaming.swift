import Foundation

nonisolated enum ScreenshotOutputCaptureType: String, Sendable {
    case fullscreen
    case window
    case area
    case scrolling
}

enum ScreenshotFileNaming {
    static let defaultTemplate = "Upshot_{date}-{time}"
    static let tokens = ["{date}", "{time}", "{app}", "{type}", "{counter}"]

    static var nextCounter: Int {
        let current = max(0, UpshotStorage.defaults.integer(forKey: UpshotPreferences.screenshotFilenameCounterKey))
        return current < Int.max ? current + 1 : 1
    }

    static func captureFileName(
        date: Date = Date(),
        appName: String,
        captureType: ScreenshotOutputCaptureType,
        outputScale: CGFloat,
        template: String? = nil,
        counter: Int? = nil
    ) -> String {
        let selectedCounter = counter ?? nextCounter
        if counter == nil {
            UpshotStorage.defaults.set(selectedCounter, forKey: UpshotPreferences.screenshotFilenameCounterKey)
        }
        let requestedTemplate = template ?? UpshotPreferences.screenshotFilenameTemplate
        let selectedTemplate = templateError(requestedTemplate) == nil ? requestedTemplate : defaultTemplate
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = "yyyy-MM-dd"
        let dateText = formatter.string(from: date)
        formatter.dateFormat = "HH-mm-ss"
        let replacements = [
            "{date}": dateText,
            "{time}": formatter.string(from: date),
            "{app}": appName.isEmpty ? "Upshot" : appName,
            "{type}": captureType.rawValue,
            "{counter}": String(format: "%04ld", selectedCounter)
        ]
        var stem = selectedTemplate
        let matches = tokenExpression.matches(in: stem, range: NSRange(stem.startIndex..., in: stem))
        for match in matches.reversed() {
            guard let range = Range(match.range, in: stem), let replacement = replacements[String(stem[range])] else { continue }
            stem.replaceSubrange(range, with: replacement)
        }
        return applyingRetinaSuffix(to: "\(sanitizedStem(stem)).png", outputScale: outputScale)
    }

    static func templateError(_ template: String) -> String? {
        guard !template.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "Enter a filename template."
        }
        var remaining = template
        for token in tokens { remaining = remaining.replacingOccurrences(of: token, with: "") }
        if remaining.contains("{") || remaining.contains("}") {
            return "Supported tokens: \(tokens.joined(separator: ", "))."
        }
        return nil
    }

    static func sanitizedStem(_ value: String) -> String {
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/:\\"))
        var result = value.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        while result.utf8.count > 180 { result.removeLast() }
        return result.isEmpty ? "Upshot" : result
    }

    static func fileName(date: Date = Date(), extension pathExtension: String = "png") -> String {
        "Upshot_\(timestampFormatter.string(from: date)).\(pathExtension)"
    }

    static func applyingRetinaSuffix(to fileName: String, outputScale: CGFloat) -> String {
        guard UpshotPreferences.screenshotRetinaSuffix, outputScale >= 1.5 else { return fileName }
        let url = URL(fileURLWithPath: fileName)
        let stem = url.deletingPathExtension().lastPathComponent
        guard !stem.hasSuffix("@2x") else { return fileName }
        let result = "\(stem)@2x.\(url.pathExtension)"
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

    private static let tokenExpression = try! NSRegularExpression(pattern: "\\{[^{}]+\\}")
}
