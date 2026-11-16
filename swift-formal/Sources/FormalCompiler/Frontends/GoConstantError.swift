enum GoConstantError: Error, CustomStringConvertible {
    case invalidLiteral, typeMismatch, unsupportedOperator, precisionLimit, nestedComparison
    var description: String {
        switch self {
        case .invalidLiteral: "Invalid Go integer constant"
        case .typeMismatch: "Go constant operand types differ"
        case .unsupportedOperator: "Unsupported Go constant operator"
        case .precisionLimit: "Go constant exceeds the 76-digit profile precision budget"
        case .nestedComparison: "Nested or chained comparisons are unsupported"
        }
    }
}
