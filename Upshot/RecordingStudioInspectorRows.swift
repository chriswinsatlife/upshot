import SwiftUI

struct StudioInspectorGroup<Content: View, Accessory: View>: View {
    let title: String
    var isOn: Binding<Bool>? = nil
    var toggleTitle: String? = nil
    @ViewBuilder var accessory: () -> Accessory
    @ViewBuilder var content: () -> Content

    init(
        _ title: String,
        isOn: Binding<Bool>? = nil,
        toggleTitle: String? = nil,
        @ViewBuilder accessory: @escaping () -> Accessory,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.isOn = isOn
        self.toggleTitle = toggleTitle
        self.accessory = accessory
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.ml) {
            HStack(spacing: Space.m) {
                InterfaceSectionHeader(title)
                Spacer(minLength: Space.l)
                accessory()
                if let isOn {
                    InspectorToggle(
                        toggleTitle ?? title,
                        isOn: Binding(
                            get: { isOn.wrappedValue },
                            set: { value in withAnimation(.morphIfAllowed) { isOn.wrappedValue = value } }
                        )
                    )
                }
            }
            .frame(minHeight: InterfaceMetrics.rowMinimumHeight)

            VStack(alignment: .leading, spacing: Space.m) {
                content()
            }
            .disabled(!(isOn?.wrappedValue ?? true))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension StudioInspectorGroup where Accessory == EmptyView {
    init(
        _ title: String,
        isOn: Binding<Bool>? = nil,
        toggleTitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title, isOn: isOn, toggleTitle: toggleTitle, accessory: { EmptyView() }, content: content)
    }
}

struct StudioInspectorPickerRow<Value: Hashable, Options: View>: View {
    let title: String
    @Binding var selection: Value
    @ViewBuilder var options: () -> Options

    init(_ title: String, selection: Binding<Value>, @ViewBuilder options: @escaping () -> Options) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        InterfaceRow(title) {
            Picker(title, selection: $selection) {
                options()
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
    }
}

struct StudioInspectorModeSwitchRow<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [InterfaceModeSwitchOption<Value>]

    init(_ title: String, selection: Binding<Value>, options: [InterfaceModeSwitchOption<Value>]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        InterfaceRow(title) {
            InterfaceModeSwitch(title, selection: $selection, options: options)
        }
    }
}
