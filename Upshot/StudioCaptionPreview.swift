import Foundation
import SwiftUI

struct StudioCaptionPreview: View {
    @Bindable var model: RecordingStudioModel
    let canvasSize: CGSize
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var edit: Edit?
    @State private var draft = ""
    @State private var timeline = StudioCaptionTimeline(cues: [], words: [])
    @FocusState private var editorFocused: Bool

    private struct Edit {
        var cue: RecordingSubtitleCue
        var textRange: Range<String.Index>
    }

    var body: some View {
        let time = model.sourceTime(atEditorTime: model.displayTime)
        let renderSize = model.basePreviewCanvasSize
        var layoutStyle = model.subtitleStyle
        if edit != nil { layoutStyle.revealsWords = false }
        let frame = StudioCaptionRenderer.layout(timeline: timeline, style: layoutStyle,
                                                canvasSize: renderSize, time: time, reducedMotion: reducedMotion)
        let scale = canvasSize.width / max(1, renderSize.width)
        return ZStack(alignment: .topLeading) {
            Canvas { graphics, _ in
                guard let frame else { return }
                graphics.withCGContext { context in
                    context.scaleBy(x: scale, y: scale)
                    StudioCaptionRenderer.draw(frame, style: model.subtitleStyle, time: time, in: context)
                }
            }
            .allowsHitTesting(false)

            if let frame {
                let rect = frame.rect
                if edit != nil {
                    TextField("Caption", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(model.subtitleStyle.preset == .serif
                              ? .custom("TimesNewRomanPSMT", size: frame.fontSize * scale)
                              : .system(size: frame.fontSize * scale))
                        .multilineTextAlignment(.center)
                        .focused($editorFocused)
                        .onSubmit { commit() }
                        .onKeyPress(.return, phases: .down) { press in
                            if press.modifiers.contains(.shift) { return .ignored }
                            commit()
                            return .handled
                        }
                        .onExitCommand { cancel() }
                        .padding(.horizontal, frame.padding.width * scale)
                        .padding(.vertical, frame.padding.height * scale)
                        .background(.background)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .position(x: rect.midX * scale, y: rect.midY * scale)
                        .onChange(of: editorFocused) { _, focused in
                            if !focused { commit() }
                        }
                } else {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .position(x: rect.midX * scale, y: (rect.midY + frame.translation) * scale)
                        .focusable()
                        .onTapGesture(count: 2) { begin(frame) }
                        .onKeyPress(.return) { begin(frame); return .handled }
                        .onKeyPress(.space) { begin(frame); return .handled }
                        .accessibilityLabel("Edit caption")
                        .accessibilityAction { begin(frame) }
                }
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .onChange(of: model.subtitleCues, initial: true) { _, _ in rebuildTimeline() }
        .onChange(of: model.transcriptWords, initial: true) { _, _ in rebuildTimeline() }
        .onChange(of: model.isPlaying) { _, playing in
            if playing { commit() }
        }
    }

    private func begin(_ frame: StudioCaptionRenderer.Frame) {
        let ranges = tokenRanges(in: frame.cue.source.text)
        guard frame.pageRange.lowerBound >= 0, frame.pageRange.upperBound <= ranges.count, !frame.pageRange.isEmpty else {
            AppLog.event("recording", "studio_caption_preview_edit_range_failed")
            return
        }
        let range = ranges[frame.pageRange.lowerBound].lowerBound..<ranges[frame.pageRange.upperBound - 1].upperBound
        model.pause()
        model.seek(to: model.displayTime)
        edit = Edit(cue: frame.cue.source, textRange: range)
        draft = String(frame.cue.source.text[range])
        editorFocused = true
        AppLog.event("recording", "studio_caption_preview_edit_started")
    }

    private func rebuildTimeline() {
        timeline = StudioCaptionTimeline(cues: model.subtitleCues, words: model.transcriptWords)
    }

    private func commit() {
        guard let edit else { return }
        self.edit = nil
        editorFocused = false
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            AppLog.event("recording", "studio_caption_preview_edit_empty")
            return
        }
        guard model.subtitleCues.first(where: { $0.id == edit.cue.id })?.text == edit.cue.text else {
            AppLog.event("recording", "studio_caption_preview_edit_conflict")
            return
        }
        var result = edit.cue.text
        result.replaceSubrange(edit.textRange, with: text)
        model.updateSubtitleText(id: edit.cue.id, text: result)
        AppLog.event("recording", "studio_caption_preview_edit_committed")
    }

    private func tokenRanges(in original: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start: String.Index?
        for index in original.indices {
            if original[index].isWhitespace {
                if let tokenStart = start { ranges.append(tokenStart..<index) }
                start = nil
            } else if start == nil {
                start = index
            }
        }
        if let start { ranges.append(start..<original.endIndex) }
        return ranges
    }

    private func cancel() {
        edit = nil
        editorFocused = false
        AppLog.event("recording", "studio_caption_preview_edit_cancelled")
    }
}
