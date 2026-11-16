public enum ResultStatus {
    public enum Generation: String, Codable, Sendable {
        case generated = "GENERATED"
        case unsupported = "UNSUPPORTED"
        case failed = "FAILED"
        case draftUnvalidated = "DRAFT_UNVALIDATED"
    }

    public enum Translation: String, Codable, Sendable {
        case validated = "VALIDATED"
        case unvalidated = "UNVALIDATED"
        case mismatch = "MISMATCH"
    }

    public enum PropertyVerification: String, Codable, Sendable {
        case notRequested = "NOT_REQUESTED"
        case modelChecked = "MODEL_CHECKED"
        case proved = "PROVED"
        case counterexample = "COUNTEREXAMPLE"
        case unknown = "UNKNOWN"
        case unproved = "UNPROVED"
    }
}
