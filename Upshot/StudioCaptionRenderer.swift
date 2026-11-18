import AppKit
import CoreGraphics
import CoreImage
import CoreText
import Foundation
import SwiftUI

nonisolated struct StudioCaptionTimeline: Sendable {
    struct Word: Sendable {
        var text: String
        var start: TimeInterval
        var end: TimeInterval
        var forcedBreak: Bool
    }

    struct Cue: Sendable {
        var source: RecordingSubtitleCue
        var words: [Word]
        var hasRecognizedTiming: Bool
        var coverageEnd: TimeInterval
        var hasFollowingCoverage: Bool
    }

    var cues: [Cue]

    init(cues: [RecordingSubtitleCue], words: [RecordingTranscriptWord]) {
        let sorted = cues.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        let timed = words.filter { $0.start.isFinite && $0.end.isFinite && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        func lowerBound(_ time: TimeInterval) -> Int {
            var low = 0
            var high = timed.count
            while low < high {
                let middle = (low + high) / 2
                if timed[middle].start < time { low = middle + 1 } else { high = middle }
            }
            return low
        }
        self.cues = sorted.enumerated().compactMap { index, cue in
            var tokens: [(text: String, forcedBreak: Bool)] = []
            for line in cue.text.components(separatedBy: .newlines) {
                for (wordIndex, token) in line.split(whereSeparator: \.isWhitespace).enumerated() {
                    tokens.append((String(token), wordIndex == 0 && !tokens.isEmpty))
                }
            }
            guard !tokens.isEmpty else { return nil }
            let recognized = Array(timed[lowerBound(cue.start - 0.001)..<lowerBound(cue.end)])
            let hasRecognizedTiming = recognized.count == tokens.count
            let duration = (cue.end - cue.start) / Double(tokens.count)
            let captionWords = tokens.enumerated().map { wordIndex, token in
                Word(
                    text: token.text,
                    start: hasRecognizedTiming ? recognized[wordIndex].start : cue.start + Double(wordIndex) * duration,
                    end: hasRecognizedTiming ? recognized[wordIndex].end : cue.start + Double(wordIndex + 1) * duration,
                    forcedBreak: token.forcedBreak
                )
            }
            let next = index + 1 < sorted.count ? sorted[index + 1] : nil
            let bridges = next.map { $0.start - cue.end < 0.5 } ?? false
            return Cue(
                source: cue,
                words: captionWords,
                hasRecognizedTiming: hasRecognizedTiming,
                coverageEnd: bridges ? max(cue.end, next?.start ?? cue.end) : cue.end,
                hasFollowingCoverage: bridges
            )
        }
    }

    func cue(at time: TimeInterval) -> Cue? {
        guard time.isFinite else { return nil }
        var low = 0
        var high = cues.count
        while low < high {
            let middle = (low + high) / 2
            if cues[middle].source.start <= time { low = middle + 1 } else { high = middle }
        }
        guard low > 0, time < cues[low - 1].coverageEnd else { return nil }
        return cues[low - 1]
    }
}

nonisolated enum StudioCaptionRenderer {
    struct Line {
        var range: Range<Int>
        var width: CGFloat
    }

    struct Frame {
        var cue: StudioCaptionTimeline.Cue
        var lines: [Line]
        var font: CTFont
        var fontSize: CGFloat
        var rect: CGRect
        var padding: CGSize
        var opacity: CGFloat
        var translation: CGFloat
        var scale: CGFloat
        var pageRange: Range<Int>
    }

    private static let imageContext = CIContext(options: [.cacheIntermediates: false])

    static func layout(
        timeline: StudioCaptionTimeline,
        style requestedStyle: SubtitleBarStyle,
        canvasSize: CGSize,
        time: TimeInterval,
        reducedMotion: Bool = false
    ) -> Frame? {
        guard canvasSize.width > 0, canvasSize.height > 0,
              let cue = timeline.cue(at: time) else { return nil }
        let style = requestedStyle.normalized
        let fontSize = max(14, CGFloat(style.fontSize) * canvasSize.width * CGFloat(style.maximumWidth / 100) / (1920 * 0.62))
        let font = style.preset == .serif
            ? CTFontCreateWithName("TimesNewRomanPSMT" as CFString, fontSize, nil)
            : CTFontCreateWithName(NSFont.systemFont(ofSize: fontSize, weight: .regular).fontName as CFString, fontSize, nil)
        let padding = CGSize(width: fontSize * 0.55, height: fontSize * 0.22)
        let maximumWidth = max(fontSize * 4, canvasSize.width * CGFloat(style.maximumWidth / 100) - padding.width * 2)
        let lines = wrap(cue.words, font: font, maximumWidth: maximumWidth)
        guard !lines.isEmpty else { return nil }
        let totalPages = (lines.count + style.maximumRows - 1) / style.maximumRows
        var pages: [(lines: [Line], start: TimeInterval, end: TimeInterval)] = []
        var lineIndex = 0
        for pageIndex in 0..<totalPages {
            let count = min(style.maximumRows, (lines.count - lineIndex + totalPages - pageIndex - 1) / (totalPages - pageIndex))
            let pageLines = Array(lines[lineIndex..<(lineIndex + count)])
            let first = pageLines[0].range.lowerBound
            let last = pageLines[pageLines.count - 1].range.upperBound - 1
            pages.append((pageLines, pageIndex == 0 ? cue.source.start : cue.words[first].start, cue.words[last].end))
            lineIndex += count
        }
        for index in pages.indices {
            pages[index].end = index + 1 < pages.count ? pages[index + 1].start : cue.coverageEnd
        }
        guard let pageIndex = pages.lastIndex(where: { time >= $0.start && time < $0.end }) else { return nil }
        let page = pages[pageIndex]
        let first = page.lines[0].range.lowerBound
        let last = page.lines[page.lines.count - 1].range.upperBound
        let visibleLines: [Line]
        if style.revealsWords {
            visibleLines = page.lines.compactMap { line in
                guard let revealed = line.range.last(where: { cue.words[$0].start <= time }) else { return nil }
                let range = line.range.lowerBound..<(revealed + 1)
                let text = cue.words[range].map(\.text).joined(separator: " ")
                let width = CGFloat(CTLineGetTypographicBounds(textLine(text, font: font, color: CGColor(gray: 1, alpha: 1)), nil, nil, nil))
                return Line(range: range, width: width)
            }
        } else {
            visibleLines = page.lines
        }
        guard !visibleLines.isEmpty else { return nil }
        let size = CGSize(
            width: min(canvasSize.width * CGFloat(style.maximumWidth / 100) + padding.width * 2,
                       (visibleLines.map(\.width).max() ?? 0) + padding.width * 2),
            height: CGFloat(visibleLines.count) * fontSize * 1.4 + padding.height * 2
        )
        let rect = CGRect(
            x: (canvasSize.width - size.width) / 2,
            y: canvasSize.height * (1 - CGFloat(style.bottomOffset / 100)) - size.height,
            width: size.width,
            height: size.height
        )
        let animation = reducedMotion ? StudioCaptionAnimation.none : style.animation
        let duration: Double = animation == .pop ? 0.09 : 0.18
        let enter = min(1, max(0, (time - page.start) / duration))
        let spokenEnd = cue.words[first..<last].map(\.end).max() ?? page.start
        let exitDuration = cue.hasRecognizedTiming ? min(duration, max(0, page.end - spokenEnd)) : duration
        let exits = pageIndex == pages.count - 1 && !cue.hasFollowingCoverage && animation != .none
        let exit = exits && exitDuration > 0 ? min(1, max(0, (page.end - time) / exitDuration)) : 1
        let visibility = CGFloat(min(enter, exit))
        let opacity: CGFloat
        let translation: CGFloat
        let scale: CGFloat
        switch animation {
        case .none: (opacity, translation, scale) = (1, 0, 1)
        case .fade: (opacity, translation, scale) = (0.3 + visibility * 0.7, 0, 1)
        case .rise: (opacity, translation, scale) = (0.25 + visibility * 0.75, (1 - visibility) * 18, 0.985 + visibility * 0.015)
        case .pop: (opacity, translation, scale) = (0.35 + visibility * 0.65, (1 - visibility) * 8, 0.94 + visibility * 0.06)
        }
        return Frame(cue: cue, lines: visibleLines, font: font, fontSize: fontSize, rect: rect, padding: padding,
                     opacity: exits ? opacity * CGFloat(exit) : opacity, translation: translation, scale: scale, pageRange: first..<last)
    }

    static func draw(_ frame: Frame, style requestedStyle: SubtitleBarStyle, time: TimeInterval, in context: CGContext) {
        let style = requestedStyle.normalized
        context.saveGState()
        context.translateBy(x: frame.rect.midX, y: frame.rect.midY + frame.translation)
        context.scaleBy(x: frame.scale, y: frame.scale)
        context.setAlpha(frame.opacity)
        let box = CGRect(x: -frame.rect.width / 2, y: -frame.rect.height / 2, width: frame.rect.width, height: frame.rect.height)
        let radius = CGFloat(style.boxRadius) * frame.fontSize / 30
        let path = RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: box).cgPath
        context.addPath(path)
        context.setFillColor(CGColor(gray: style.preset == .serif ? 1 : 0, alpha: style.backgroundOpacity))
        context.fillPath()
        if style.preset == .serif {
            let border = frame.fontSize * 0.1
            let inset = box.insetBy(dx: border / 2, dy: border / 2)
            context.addPath(RoundedRectangle(cornerRadius: max(0, radius - border / 2), style: .continuous).path(in: inset).cgPath)
            context.setStrokeColor(CGColor(gray: 0, alpha: 0.12))
            context.setLineWidth(border)
            context.strokePath()
        }
        let active = frame.cue.words.lastIndex { $0.start <= time }
        let ascent = CTFontGetAscent(frame.font)
        let descent = CTFontGetDescent(frame.font)
        let lineHeight = frame.fontSize * 1.4
        for (lineIndex, line) in frame.lines.enumerated() {
            let lineText = frame.cue.words[line.range].map(\.text).joined(separator: " ")
            let measured = textLine(lineText, font: frame.font, color: StudioCaptionColor.color(style.textColor))
            var offset = 0
            for index in line.range {
                let word = frame.cue.words[index]
                if index > line.range.lowerBound { offset += 1 }
                let startX = CTLineGetOffsetForStringIndex(measured, offset, nil)
                offset += word.text.utf16.count
                let endX = CTLineGetOffsetForStringIndex(measured, offset, nil)
                let x = -line.width / 2 + min(startX, endX)
                let y = box.minY + frame.padding.height + CGFloat(lineIndex) * lineHeight + (lineHeight - ascent - descent) / 2
                let isActive = frame.cue.hasRecognizedTiming && index == active
                let highlighted = style.highlightsSpokenWord && isActive
                let color = highlighted ? style.highlightTextColor : (frame.cue.hasRecognizedTiming && !isActive ? style.inactiveTextColor : style.textColor)
                let elapsed = min(1, max(0, (time - word.start) / 0.14))
                let reveal = style.revealsWords ? CGFloat(1 - pow(1 - elapsed, 3)) : 1
                guard reveal > 0 else { continue }
                context.saveGState()
                context.setAlpha(frame.opacity * reveal)
                if highlighted {
                    let highlight = CGRect(x: x - frame.fontSize * 0.12, y: y - frame.fontSize * 0.06,
                                           width: abs(endX - startX) + frame.fontSize * 0.24,
                                           height: ascent + descent + frame.fontSize * 0.12)
                    context.addPath(RoundedRectangle(cornerRadius: frame.fontSize * 0.22, style: .continuous).path(in: highlight).cgPath)
                    context.setFillColor(StudioCaptionColor.color(style.highlightFill))
                    context.fillPath()
                }
                let wordLine = textLine(word.text, font: frame.font, color: StudioCaptionColor.color(color))
                drawWord(wordLine, at: CGPoint(x: x, y: y + ascent), size: CGSize(width: abs(endX - startX), height: ascent + descent),
                         ascent: ascent, blur: (1 - reveal) * frame.fontSize * 0.18, in: context)
                context.restoreGState()
            }
        }
        context.restoreGState()
    }

    private static func textLine(_ text: String, font: CTFont, color: CGColor) -> CTLine {
        CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]))
    }

    private static func drawWord(_ line: CTLine, at baseline: CGPoint, size: CGSize, ascent: CGFloat, blur: CGFloat, in context: CGContext) {
        guard blur > 0.01 else {
            context.saveGState()
            context.translateBy(x: baseline.x, y: baseline.y)
            context.scaleBy(x: 1, y: -1)
            context.textMatrix = .identity
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
            return
        }
        let margin = ceil(blur * 3 + 2)
        let width = max(1, Int(ceil(size.width + margin * 2)))
        let height = max(1, Int(ceil(size.height + margin * 2)))
        guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                     space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            AppLog.event("rendering", "caption_reveal_bitmap_failed")
            drawWord(line, at: baseline, size: size, ascent: ascent, blur: 0, in: context)
            return
        }
        bitmap.textPosition = CGPoint(x: margin, y: CGFloat(height) - margin - ascent)
        CTLineDraw(line, bitmap)
        guard let image = bitmap.makeImage() else {
            AppLog.event("rendering", "caption_reveal_image_failed")
            drawWord(line, at: baseline, size: size, ascent: ascent, blur: 0, in: context)
            return
        }
        let input = CIImage(cgImage: image)
        let filtered = input.applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur])
        guard let output = imageContext.createCGImage(filtered, from: input.extent) else {
            AppLog.event("rendering", "caption_reveal_blur_failed")
            drawWord(line, at: baseline, size: size, ascent: ascent, blur: 0, in: context)
            return
        }
        context.saveGState()
        context.translateBy(x: baseline.x - margin, y: baseline.y - ascent - margin + CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        context.draw(output, in: CGRect(x: 0, y: 0, width: width, height: height))
        context.restoreGState()
    }

    private static func wrap(_ words: [StudioCaptionTimeline.Word], font: CTFont, maximumWidth: CGFloat) -> [Line] {
        guard !words.isEmpty else { return [] }
        let color = CGColor(gray: 1, alpha: 1)
        func measure(_ text: String) -> CGFloat { CGFloat(CTLineGetTypographicBounds(textLine(text, font: font, color: color), nil, nil, nil)) }
        let widths = words.map { measure($0.text) }
        let segments = words.map { measure(" " + $0.text) }
        var costs = [CGFloat](repeating: .infinity, count: words.count + 1)
        var breaks = [Int](repeating: words.count, count: words.count)
        costs[words.count] = 0
        for start in words.indices.reversed() {
            var width = widths[start]
            for end in start..<words.count {
                if end > start {
                    if words[end].forcedBreak { break }
                    width += segments[end]
                }
                if width > maximumWidth && end > start { break }
                let slack = max(0, maximumWidth - width)
                let fullness = width / maximumWidth
                let penalty = end == words.count - 1 ? slack * slack * 0.18 : slack * slack + max(0, 0.72 - fullness) * 26000
                let cost = penalty + costs[end + 1]
                if cost < costs[start] { costs[start] = cost; breaks[start] = end + 1 }
            }
        }
        var result: [Line] = []
        var start = 0
        while start < words.count {
            let end = max(start + 1, breaks[start])
            result.append(Line(range: start..<end, width: measure(words[start..<end].map(\.text).joined(separator: " "))))
            start = end
        }
        return result
    }
}
