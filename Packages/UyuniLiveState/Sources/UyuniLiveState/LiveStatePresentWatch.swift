import AppKit

final class LiveStatePresentWatch: @unchecked Sendable {
    static let shared = LiveStatePresentWatch()
    static let defaultLimitSeconds: Double = 30
    static let mainThreadSilenceLimitSeconds: Double = 2

    private let lock = NSLock()
    private var generation = 0
    private var activeGeneration: Int?
    private var stateName = ""
    private var step = ""
    private var began: TimeInterval = 0
    private var stepBegan: TimeInterval = 0
    private var reported = false
    private var mainHeartbeat: TimeInterval = ProcessInfo.processInfo.systemUptime
    private var timer: DispatchSourceTimer?
    let limitSeconds: Double
    var onTimeout: (@Sendable (_ generation: Int, _ state: String, _ step: String, _ seconds: Double, _ handled: @escaping @Sendable () -> Void) -> Void)?

    init() {
        let configured = ProcessInfo.processInfo.environment["UYUNI_LIVE_STATE_PRESENT_TIMEOUT_SECONDS"].flatMap(Double.init)
        limitSeconds = configured.map { max(1, $0) } ?? Self.defaultLimitSeconds
    }

    func start() {
        let source = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .userInitiated))
        source.schedule(deadline: .now() + 0.5, repeating: 0.5)
        source.setEventHandler { [self] in check() }
        source.resume()
        timer = source
    }

    func begin(_ state: String) -> Int {
        lock.lock()
        defer { lock.unlock() }
        generation += 1
        activeGeneration = generation
        stateName = state
        step = "begin"
        began = ProcessInfo.processInfo.systemUptime
        stepBegan = began
        reported = false
        return generation
    }

    func enter(_ name: String, generation expected: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard activeGeneration == expected else { return }
        step = name
        stepBegan = ProcessInfo.processInfo.systemUptime
    }

    func end(_ expected: Int) {
        lock.lock()
        defer { lock.unlock() }
        if activeGeneration == expected { activeGeneration = nil }
    }

    func isCurrent(_ expected: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return activeGeneration == expected
    }

    func heartbeat() {
        lock.lock()
        mainHeartbeat = ProcessInfo.processInfo.systemUptime
        lock.unlock()
    }

    private func check() {
        lock.lock()
        let now = ProcessInfo.processInfo.systemUptime
        guard let active = activeGeneration, !reported, now - began >= limitSeconds else {
            lock.unlock()
            return
        }
        reported = true
        activeGeneration = nil
        let state = stateName
        let stepName = step
        let seconds = now - began
        let stepSeconds = now - stepBegan
        let silence = now - mainHeartbeat
        lock.unlock()
        let fields: [String: Any] = ["state": state, "step": stepName, "seconds": seconds.rounded(toPlaces: 3), "stepSeconds": stepSeconds.rounded(toPlaces: 3),
                                     "mainThreadSilenceSeconds": silence.rounded(toPlaces: 3), "limitSeconds": limitSeconds]
        let handled = DispatchSemaphore(value: 0)
        if silence < Self.mainThreadSilenceLimitSeconds, let onTimeout {
            onTimeout(active, state, stepName, seconds) { handled.signal() }
            if handled.wait(timeout: .now() + Self.mainThreadSilenceLimitSeconds) == .success {
                LiveStateLog.event("live_state_present_timed_out", fields.merging(["mainThreadResponding": true]) { first, _ in first })
                return
            }
        }
        let reason = "The present of \(state) did not finish within \(Int(limitSeconds)) seconds; the step that did not finish is \(stepName), and the main thread did not respond within \(Int(Self.mainThreadSilenceLimitSeconds)) seconds."
        LiveStateLog.event("live_state_present_timed_out", fields.merging(["mainThreadResponding": false, "exitStatus": 1]) { first, _ in first })
        LiveStateOutput.write(["event": "live_state_failed", "reason": reason])
        exit(1)
    }
}
