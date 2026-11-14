import Foundation

enum LiveStateOutput {
    static func write(_ fields: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        FileHandle.standardOutput.write(data + Data("\n".utf8))
    }
}

enum LiveStateLog {
    static let processIdentifier = Int(ProcessInfo.processInfo.processIdentifier)

    static func event(_ name: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = name
        record["processIdentifier"] = processIdentifier
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        guard JSONSerialization.isValidJSONObject(record),
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys, .withoutEscapingSlashes]) else {
            FileHandle.standardError.write(Data("{\"event\":\"log_encoding_failed\",\"name\":\(name.debugDescription)}\n".utf8))
            return
        }
        FileHandle.standardError.write(data + Data("\n".utf8))
    }

    static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let elapsed = ContinuousClock.now - start
        let components = elapsed.components
        return (Double(components.seconds) * 1000 + Double(components.attoseconds) / 1e15).rounded(toPlaces: 3)
    }
}

extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
