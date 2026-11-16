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

    case numberAdd, numberSubtract, numberMultiply, numberDivide, numberRemainder
    case numberNegate, numberAbsolute, numberEqual, numberLessThan, numberLessEqual
    case numberSameValue, numberIsNaN, numberIsFinite, numberIsInteger, numberIsSafeInteger, numberTruthy

    public var isNumber: Bool { rawValue.hasPrefix("number") }
    public var returnsFlag: Bool {
        [.signedLessThan, .unsignedLessThan, .equal, .numberEqual, .numberLessThan, .numberLessEqual,
         .numberSameValue, .numberIsNaN, .numberIsFinite, .numberIsInteger, .numberIsSafeInteger, .numberTruthy].contains(self)
    }
    public var returnsOverflow: Bool {
        switch self {
        case .signedAddOverflow, .signedSubtractOverflow, .signedMultiplyOverflow,
             .unsignedAddOverflow, .unsignedSubtractOverflow, .unsignedMultiplyOverflow: true
        default: false
        }
    }
}
