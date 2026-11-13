import CoreGraphics
import Foundation

nonisolated struct SmartRedactionRegion: Equatable, Sendable {
    var text: String
    var bounds: CGRect
}

nonisolated enum SmartRedactionRecognizer {
    private static let unitRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    static func sensitiveRegions(at url: URL) async -> [SmartRedactionRegion] {
        do {
            return try await recognizeSensitiveRegions(at: url)
        } catch is CancellationError {
            return []
        } catch {
            AppLog.event("annotation", "smart_redaction", fields: ["error": AppLog.error(error), "failure": ImageTextRecognizer.failureTitle(for: error)])
            await CaptureTextFeedbackPresenter.shared.showFailure(title: ImageTextRecognizer.failureTitle(for: error), displayID: nil)
            return []
        }
    }

    static func recognizeSensitiveRegions(at url: URL) async throws -> [SmartRedactionRegion] {
        let image = try await ImageTextRecognizer.loadImage(at: url)
        let lines = try await ImageTextRecognizer.recognizeLines(in: image, requiresBounds: true, includeCharacterBounds: true)
        try Task.checkCancellation()
        let padding = normalizedPadding(for: CGSize(width: image.width, height: image.height))
        let regions = uniqued(lines.flatMap { line -> [SmartRedactionRegion] in
            sensitiveRanges(in: line.text).compactMap { range in
                guard let lineBounds = line.bounds(for: range) else { return nil }
                let bounds = lineBounds.insetBy(dx: -padding.width, dy: -padding.height)
                    .intersection(unitRect).standardized
                guard bounds.width >= 0.001, bounds.height >= 0.001 else { return nil }
                return SmartRedactionRegion(text: String(line.text[range]), bounds: bounds)
            }
        })
        AppLog.event("annotation", "smart_redaction_recognition_completed", fields: ["lines": String(describing: lines.count), "regions": String(describing: regions.count)])
        return regions
    }

    nonisolated private static func sensitiveRanges(in text: String) -> [Range<String.Index>] {
        let textRange = NSRange(text.startIndex..<text.endIndex, in: text)
        var ranges: [Range<String.Index>] = []

        for rule in regexRules {
            guard let regex = try? NSRegularExpression(pattern: rule.pattern, options: [.caseInsensitive]) else {
                continue
            }

            for match in regex.matches(in: text, range: textRange) {
                guard let range = Range(match.range, in: text),
                      rule.accepts(String(text[range])) else {
                    continue
                }

                ranges.append(range)
            }
        }

        if let valueRange = secretValueRange(in: text) {
            ranges.append(valueRange)
        }

        return mergedRanges(ranges, in: text)
    }

    nonisolated private static var regexRules: [RegexRule] {
        [
            RegexRule(#"\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#),
            RegexRule(#"\bhttps?://[^\s<>"']+"#),
            RegexRule(#"\bwww\.[^\s<>"']+"#),
            RegexRule(#"\b\d{1,3}(?:\.\d{1,3}){3}\b"#, accepts: isLikelyIPv4Address),
            RegexRule(#"\b(?:\+?\d[\d\s().-]{7,}\d)\b"#, accepts: isLikelyPhoneNumber),
            RegexRule(#"\b(?:\d[ -]*?){13,19}\b"#, accepts: isLikelyPaymentCard),
            RegexRule(#"\b[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b"#),
            RegexRule(#"\b(?:sk|pk|rk|ghp|gho|ghu|github_pat|xox[baprs]?|AKIA|ASIA|AIza|ya29)[A-Za-z0-9_-]{8,}\b"#),
            RegexRule(#"\b[A-Za-z0-9_-]{24,}\b"#, accepts: isLikelyOpaqueToken)
        ]
    }

    nonisolated private static func secretValueRange(in text: String) -> Range<String.Index>? {
        let pattern = #"\b(password|passcode|secret|api\s*key|access\s*key|client\s*secret|private\s*key|authorization|bearer|token)\b\s*[:=]\s*\S+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)),
              let matchRange = Range(match.range, in: text) else {
            return nil
        }

        guard let separator = text[matchRange].firstIndex(where: { $0 == ":" || $0 == "=" }) else {
            return matchRange
        }

        let valueStart = text.index(after: separator)
        let trimmedStart = text[valueStart..<matchRange.upperBound].firstIndex { !$0.isWhitespace } ?? valueStart
        guard trimmedStart < matchRange.upperBound else {
            return matchRange
        }

        return trimmedStart..<matchRange.upperBound
    }

    nonisolated private static func normalizedPadding(for imageSize: CGSize) -> CGSize {
        let width = max(imageSize.width, 1)
        let height = max(imageSize.height, 1)
        return CGSize(
            width: min(max(6 / width, 0.002), 0.012),
            height: min(max(4 / height, 0.002), 0.012)
        )
    }

    nonisolated private static func mergedRanges(
        _ ranges: [Range<String.Index>],
        in text: String
    ) -> [Range<String.Index>] {
        let nsRanges = ranges
            .map { NSRange($0, in: text) }
            .sorted { $0.location < $1.location }

        var merged: [NSRange] = []
        for range in nsRanges {
            guard let last = merged.last else {
                merged.append(range)
                continue
            }

            let lastEnd = last.location + last.length
            let rangeEnd = range.location + range.length
            if range.location <= lastEnd {
                merged[merged.count - 1] = NSRange(
                    location: last.location,
                    length: max(lastEnd, rangeEnd) - last.location
                )
            } else {
                merged.append(range)
            }
        }

        return merged.compactMap { Range($0, in: text) }
    }

    nonisolated private static func uniqued(_ regions: [SmartRedactionRegion]) -> [SmartRedactionRegion] {
        var output: [SmartRedactionRegion] = []
        for region in regions {
            let alreadyIncluded = output.contains { existing in
                existing.bounds.intersection(region.bounds).area >= min(existing.bounds.area, region.bounds.area) * 0.85
            }
            if !alreadyIncluded {
                output.append(region)
            }
        }
        return output
    }

    nonisolated private static func isLikelyIPv4Address(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }

    nonisolated private static func isLikelyPhoneNumber(_ value: String) -> Bool {
        let digits = value.filter(\.isNumber)
        return (8...15).contains(digits.count)
    }

    nonisolated private static func isLikelyPaymentCard(_ value: String) -> Bool {
        let digits = value.compactMap(\.wholeNumberValue)
        guard (13...19).contains(digits.count) else { return false }
        return luhnCheck(digits)
    }

    nonisolated private static func isLikelyOpaqueToken(_ value: String) -> Bool {
        let hasLetter = value.contains { $0.isLetter }
        let hasNumber = value.contains { $0.isNumber }
        guard hasLetter && hasNumber else { return false }

        let separatorCount = value.filter { $0 == "-" || $0 == "_" }.count
        return value.count >= 24 && separatorCount <= max(6, value.count / 8)
    }

    nonisolated private static func luhnCheck(_ digits: [Int]) -> Bool {
        var sum = 0
        var shouldDouble = false

        for digit in digits.reversed() {
            var value = digit
            if shouldDouble {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }
            sum += value
            shouldDouble.toggle()
        }

        return sum % 10 == 0
    }
}

nonisolated private struct RegexRule: Sendable {
    let pattern: String
    let accepts: @Sendable (String) -> Bool

    init(_ pattern: String, accepts: @escaping @Sendable (String) -> Bool = { _ in true }) {
        self.pattern = pattern
        self.accepts = accepts
    }
}

private extension CGRect {
    nonisolated var area: CGFloat {
        max(width, 0) * max(height, 0)
    }
}
