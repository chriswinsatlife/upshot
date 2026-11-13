import SwiftUI

struct AnnotationInspectorSliderRow: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: InspectorValueFormat

    static let sliderWidth: CGFloat = 104

    init(_ title: String, value: Binding<CGFloat>, range: ClosedRange<CGFloat>, format: InspectorValueFormat) {
        self.title = title
        self._value = value
        self.range = range
        self.format = format
    }

    var body: some View {
        InterfaceRow(title) {
            Slider(value: clampedValue, in: range)
                .labelsHidden()
                .controlSize(.small)
                .frame(width: Self.sliderWidth)
                .accessibilityLabel(title)
                .accessibilityValue(format.displayString(for: value))
            AnnotationInspectorValueField(title: title, value: $value, range: range, format: format)
        }
    }

    private var clampedValue: Binding<CGFloat> {
        Binding(
            get: { min(max(value, range.lowerBound), range.upperBound) },
            set: { proposedValue in
                let clamped = min(max(proposedValue, range.lowerBound), range.upperBound)
                guard clamped != value else { return }
                value = clamped
            }
        )
    }
}

struct AnnotationInspectorValueField: View {
    let title: String
    @Binding var value: CGFloat
    let range: ClosedRange<CGFloat>
    let format: InspectorValueFormat

    static let width: CGFloat = 58

    @Environment(\.isEnabled) private var isEnabled
    @State private var isEditing = false
    @State private var draftText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                HStack(spacing: 0) {
                    TextField("", text: $draftText)
                        .labelsHidden()
                        .textFieldStyle(.plain)
                        .font(.dsFieldNumeric)
                        .multilineTextAlignment(.trailing)
                        .focused($isFieldFocused)
                        .onSubmit(finishEditing)
                        .onExitCommand(perform: cancelEditing)
                        .onKeyPress(.upArrow) {
                            nudge(by: format.step)
                            return .handled
                        }
                        .onKeyPress(.downArrow) {
                            nudge(by: -format.step)
                            return .handled
                        }
                        .accessibilityLabel("\(title) value")
                }
                .interfaceFieldChrome()
                .onAppear { isFieldFocused = true }
                .onChange(of: isFieldFocused) { _, isFocused in
                    if !isFocused { finishEditing() }
                }
            } else {
                Button(action: beginEditing) {
                    InterfaceValueWithUnitLabel(value: displayParts.value, unit: displayParts.unit, unitSpacing: displayParts.spacing)
                        .opacity(isEnabled ? 1 : 0.45)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .interfaceFieldChrome()
                        .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .focusEffectDisabled()
                .help("Enter an exact value for \(title)")
                .accessibilityLabel("\(title) value")
                .accessibilityValue(format.displayString(for: value))
            }
        }
        .frame(width: Self.width)
    }

    private var displayParts: (value: String, unit: String, spacing: InterfaceUnitSpacing) {
        let text = format.displayString(for: value)
        let suffix = format.suffix
        guard !suffix.isEmpty, text.hasSuffix(suffix) else { return (text, "", .none) }
        let number = String(text.dropLast(suffix.count))
        let unit = suffix.trimmingCharacters(in: .whitespaces)
        return (number, unit, suffix.hasPrefix(" ") ? .wordSpace : .none)
    }

    private func beginEditing() {
        draftText = format.editingString(for: value)
        isEditing = true
    }

    private func finishEditing() {
        guard isEditing else { return }
        if let parsedValue = format.parse(draftText) {
            setValue(parsedValue)
        }
        isEditing = false
        isFieldFocused = false
    }

    private func cancelEditing() {
        isEditing = false
        isFieldFocused = false
    }

    private func nudge(by delta: CGFloat) {
        if let parsedValue = format.parse(draftText) {
            setValue(parsedValue + delta)
        } else {
            setValue(value + delta)
        }
        draftText = format.editingString(for: value)
    }

    private func setValue(_ proposedValue: CGFloat) {
        guard proposedValue.isFinite else { return }
        let clamped = min(max(proposedValue, range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        value = clamped
    }
}
