import SwiftUI

@MainActor
final class CounterModel: ObservableObject {
    @Published var count = 0
}

struct CounterView: View {
    static let sourceLine = #line
    @ObservedObject var model: CounterModel
    let size: CGSize

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(model.count % 2 == 0 ? Color(red: 0.1, green: 0.3, blue: 0.9) : Color(red: 0.95, green: 0.5, blue: 0.1))
                .frame(height: size.height / 2)
            Button {
                model.count += 1
                FixtureLog.event("counter_button_action", ["count": model.count])
            } label: {
                Text("Increment \(model.count)")
                    .font(.system(size: 28, weight: .semibold))
                    .frame(width: size.width, height: size.height / 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .frame(width: size.width, height: size.height)
    }
}

struct ScrollingListView: View {
    static let sourceLine = #line
    let rows: [String]
    let size: CGSize

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                        .padding(.horizontal, 24)
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct TextAndSliderView: View {
    static let sourceLine = #line
    let size: CGSize
    @State private var text = ""
    @State private var slider = 0.25

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Text: \(text)")
            TextField("Enter text", text: $text)
            Text("Slider: \(Int(slider * 100))")
            Slider(value: $slider)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(width: size.width, height: size.height)
        .onChange(of: text) { _, value in FixtureLog.event("text_changed", ["text": value]) }
        .onChange(of: slider) { _, value in FixtureLog.event("slider_changed", ["value": value]) }
    }
}

@MainActor
final class PanelModel: ObservableObject {
    @Published var presses = 0
}

struct PanelView: View {
    static let sourceLine = #line
    @ObservedObject var model: PanelModel

    var body: some View {
        VStack {
            Text("Panel presses: \(model.presses)")
            Button("Increment panel") {
                model.presses += 1
                FixtureLog.event("panel_button_action", ["count": model.presses])
            }
        }
        .frame(width: 240, height: 160)
        .background(Color.white)
        .preferredColorScheme(.light)
    }
}
