import FormalCore

struct VerificationDeadline: Sendable {
    let end: ContinuousClock.Instant
    init(seconds: Double) { end = ContinuousClock.now.advanced(by: .seconds(seconds)) }
    func remaining() throws -> Double {
        let duration = ContinuousClock.now.duration(to: end).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        guard seconds > 0 else { throw FormalDiagnostic(.timeout,"Whole verification deadline expired") }
        return seconds
    }
}
