public enum LiveStateLaunchRequest: Equatable, Sendable {
    case listLiveStates
    case presentLiveState(String)
    case invalid(reason: String)

    public static let listArgument = "--list-live-states"
    public static let presentArgument = "--present-live-state"

    public init?(arguments: [String]) {
        let values = Array(arguments.dropFirst())
        let listCount = values.filter { $0 == Self.listArgument }.count
        let presentIndices = values.indices.filter { values[$0] == Self.presentArgument }
        if listCount == 0 && presentIndices.isEmpty { return nil }
        if listCount > 0 && !presentIndices.isEmpty {
            self = .invalid(reason: "The arguments must contain either \(Self.listArgument) or \(Self.presentArgument), not both.")
        } else if listCount > 1 || presentIndices.count > 1 {
            self = .invalid(reason: "The arguments must contain \(listCount > 1 ? Self.listArgument : Self.presentArgument) once.")
        } else if let index = presentIndices.first {
            let next = index + 1
            guard next < values.count, !values[next].isEmpty, !values[next].hasPrefix("--") else {
                self = .invalid(reason: "The argument \(Self.presentArgument) must be followed by one state name.")
                return
            }
            self = .presentLiveState(values[next])
        } else {
            self = .listLiveStates
        }
    }
}
