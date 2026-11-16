public enum IROperation: String, Codable, Sendable, CaseIterable {
    case signedAddOverflow
    case signedSubtractOverflow
    case signedMultiplyOverflow
    case unsignedAddOverflow
    case unsignedSubtractOverflow
    case unsignedMultiplyOverflow
    case signedLessThan
    case unsignedLessThan
    case equal
    case and
    case or
    case xor

    public var returnsOverflow: Bool {
        switch self {
        case .signedAddOverflow, .signedSubtractOverflow, .signedMultiplyOverflow,
             .unsignedAddOverflow, .unsignedSubtractOverflow, .unsignedMultiplyOverflow: true
        default: false
        }
    }
}
