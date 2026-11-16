public struct IRExecutionResult: Sendable, Equatable {
    public enum Outcome: Sendable, Equatable {
        case returned(IRValue)
        case trapped(String)
        case failed(IRFailureKind, String)
        case boundExceeded(String)
    }

    public let outcome: Outcome
    public let steps: Int
}
