import SwiftUI

enum InterfacePresentedControlState: String, CaseIterable, Identifiable, Sendable {
    case normal
    case hover
    case pressed
    case selected
    case disabled
    case on
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .normal: "Normal"
        case .hover: "Hover"
        case .pressed: "Pressed"
        case .selected: "Selected"
        case .disabled: "Disabled"
        case .on: "On"
        case .off: "Off"
        }
    }
}

extension EnvironmentValues {
    @Entry var interfacePresentedControlState: InterfacePresentedControlState? = nil
}

struct InterfaceInteractionState: Equatable {
    var isHovered: Bool
    var isPressed: Bool
}

extension InterfacePresentedControlState? {
    func resolvedInteraction(isHovering: Bool, isPressed: Bool) -> InterfaceInteractionState {
        switch self {
        case .hover: InterfaceInteractionState(isHovered: true, isPressed: false)
        case .pressed: InterfaceInteractionState(isHovered: true, isPressed: true)
        case .some: InterfaceInteractionState(isHovered: false, isPressed: false)
        case .none: InterfaceInteractionState(isHovered: isHovering, isPressed: isPressed)
        }
    }
}

extension View {
    func interfacePresentedControlState(_ state: InterfacePresentedControlState?) -> some View {
        environment(\.interfacePresentedControlState, state)
            .disabled(state == .disabled)
    }
}
