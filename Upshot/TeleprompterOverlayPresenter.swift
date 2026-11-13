import AppKit
import CoreGraphics
import Observation
import SwiftUI

struct TeleprompterNotchShape: Shape {
    static let expandedEarRadius: CGFloat = 12

    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set {
            topCornerRadius = newValue.first
            bottomCornerRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let top = min(topCornerRadius, rect.width / 4, rect.height / 2)
        let bottom = min(bottomCornerRadius, rect.width / 4, rect.height - top)
        var path = Path()

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        path.closeSubpath()
        return path
    }
}

@Observable
final class TeleprompterOverlayModel {
    enum Mode {
        case notch(width: CGFloat, height: CGFloat)
        case pill
    }

    var mode: Mode = .pill
    var isExpanded = false
    var layout: TeleprompterScriptLayout = .empty

    var spokenWordCount = 0
    var visibleLineCount = 3
    var expandedWidth: CGFloat = 320

    static let lineHeight: CGFloat = 20
    static let textHorizontalPadding = Space.xl
    static let textBottomInset = Space.l
    static let font = Font.dsBodyEmphasis
    static let measuringFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    var textWidth: CGFloat {
        expandedWidth - Self.textHorizontalPadding * 2
    }

    var textAreaHeight: CGFloat {
        CGFloat(visibleLineCount) * Self.lineHeight
    }

    var textTopInset: CGFloat {
        switch mode {
        case .notch(_, let notchHeight):
            notchHeight + Space.s
        case .pill:
            Space.l
        }
    }

    var expandedHeight: CGFloat {
        textTopInset + textAreaHeight + Self.textBottomInset
    }

    var housingEarWidth: CGFloat {
        switch mode {
        case .notch:
            TeleprompterNotchShape.expandedEarRadius
        case .pill:
            0
        }
    }

    var expandedHousingWidth: CGFloat {
        expandedWidth + housingEarWidth * 2
    }

    var collapsedSize: CGSize {
        switch mode {
        case .notch(let width, let height):
            CGSize(width: width, height: height)
        case .pill:
            CGSize(width: 140, height: 12)
        }
    }
}

@MainActor
final class TeleprompterOverlayPresenter {
    static let shared = TeleprompterOverlayPresenter()

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.78)
    static let scrollSpring = Animation.spring(response: 0.5, dampingFraction: 0.86)

    private let model = TeleprompterOverlayModel()
    private var panel: NSPanel?

    private var hideGeneration = 0

    private init() {}

    func show(script: String, displayID: CGDirectDisplayID?) {
        guard let screen = ActiveDisplayResolver.screen(for: displayID) ?? NSScreen.main else { return }

        hideGeneration += 1
        model.mode = Self.notchMode(for: screen) ?? .pill
        model.visibleLineCount = UpshotPreferences.recordingTeleprompterLineCount
        model.expandedWidth = 320
        model.layout = TeleprompterScriptLayout(
            script: script,
            maximumLineWidth: model.textWidth,
            font: TeleprompterOverlayModel.measuringFont
        )
        model.spokenWordCount = 0
        model.isExpanded = false
        guard !model.layout.isEmpty else { return }

        let panel = panel ?? makePanel()
        PreviewWindowCaptureExclusion.shared.register(window: panel)
        position(panel, on: screen)
        panel.orderFrontRegardless()

        DispatchQueue.main.async { [model] in
            withAnimation(Self.spring) {
                model.isExpanded = true
            }
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        guard model.isExpanded else {
            panel.orderOut(nil)
            return
        }

        hideGeneration += 1
        let generation = hideGeneration
        withAnimation(Self.spring, completionCriteria: .logicallyComplete) {
            model.isExpanded = false
        } completion: { [weak self] in
            guard let self, self.hideGeneration == generation else { return }
            self.panel?.orderOut(nil)
        }
    }

    func updateProgress(spokenWordCount: Int) {
        model.spokenWordCount = max(model.spokenWordCount, spokenWordCount)
    }

    private static func notchMode(for screen: NSScreen) -> TeleprompterOverlayModel.Mode? {
        let notchHeight = screen.safeAreaInsets.top
        guard notchHeight > 0 else { return nil }

        var notchWidth: CGFloat = 200
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            notchWidth = screen.frame.width - left.width - right.width
        }
        return .notch(width: notchWidth, height: notchHeight)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.stationary, .canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        let hostingView = TeleprompterOverlayHostingView(
            rootView: TeleprompterOverlayView(model: model)
        )

        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.layer?.isOpaque = false
        panel.contentView = hostingView

        self.panel = panel
        return panel
    }

    private func position(_ panel: NSPanel, on screen: NSScreen) {

        let width = model.expandedHousingWidth + 80
        let height = model.expandedHeight + 40

        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.setFrame(
            CGRect(
                x: screen.frame.midX - width / 2,
                y: screen.frame.maxY - height,
                width: width,
                height: height
            ),
            display: false
        )
    }
}

private final class TeleprompterOverlayHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool {
        false
    }
}

struct TeleprompterOverlayView: View {
    let model: TeleprompterOverlayModel

    var body: some View {
        housing
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .environment(\.colorScheme, .dark)
    }

    private var housing: some View {
        let expanded = model.isExpanded
        let size = expanded
            ? CGSize(width: model.expandedHousingWidth, height: model.expandedHeight)
            : model.collapsedSize
        let shape = housingShape(expanded: expanded)

        return textArea
            .padding(.bottom, TeleprompterOverlayModel.textBottomInset)
            .opacity(expanded ? 1 : 0)
            .frame(width: size.width, height: size.height, alignment: .bottom)
            .background(shape.fill(Color.black))
            .clipShape(shape)
    }

    private func housingShape(expanded: Bool) -> TeleprompterNotchShape {
        switch model.mode {
        case .notch:
            TeleprompterNotchShape(
                topCornerRadius: expanded ? TeleprompterNotchShape.expandedEarRadius : 2,
                bottomCornerRadius: expanded ? Radius.panel : 9
            )
        case .pill:
            TeleprompterNotchShape(
                topCornerRadius: 0,
                bottomCornerRadius: expanded ? Radius.panel : 6
            )
        }
    }

    private var topLineIndex: Int {
        guard model.spokenWordCount > 0 else { return 0 }
        let activeWord = model.spokenWordCount - 1
        var activeLine = model.layout.lineIndex(forWord: activeWord)

        if model.layout.isLastWord(inLine: activeWord) {
            activeLine += 1
        }
        let maximumTop = max(0, model.layout.lines.count - model.visibleLineCount)
        return min(max(activeLine, 0), maximumTop)
    }

    private var textArea: some View {
        let lineHeight = TeleprompterOverlayModel.lineHeight
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.layout.lines.enumerated()), id: \.offset) { entry in
                lineText(entry.element)
                    .font(TeleprompterOverlayModel.font)
                    .lineLimit(1)
                    .frame(height: lineHeight, alignment: .leading)
            }
        }
        .frame(width: model.textWidth, alignment: .topLeading)
        .offset(y: -CGFloat(topLineIndex) * lineHeight)
        .animation(TeleprompterOverlayPresenter.scrollSpring, value: topLineIndex)
        .frame(width: model.textWidth, height: model.textAreaHeight, alignment: .top)
        .clipped()
        .mask(verticalFade)
    }

    private var verticalFade: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: .black.opacity(0), location: 0),
                .init(color: .black, location: 0.1),
                .init(color: .black, location: 0.92),
                .init(color: .black.opacity(0.25), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func lineText(_ line: [TeleprompterScriptLayout.Word]) -> Text {
        var text = Text(verbatim: "")
        for (position, word) in line.enumerated() {
            let wordText = Text(verbatim: word.text)
                .foregroundStyle(color(forWord: word.index))
            text = position == 0 ? wordText : Text("\(text) \(wordText)")
        }
        return text
    }

    private func color(forWord index: Int) -> Color {
        let spoken = model.spokenWordCount
        if index == spoken - 1 {
            return Palette.accent
        }
        if index < spoken {
            return Palette.tertiaryLabel
        }
        return Palette.label
    }
}
