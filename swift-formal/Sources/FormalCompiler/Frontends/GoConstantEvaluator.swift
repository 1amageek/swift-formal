import FormalIR

/// Evaluates untyped constant subtrees without imposing a contextual machine width.
struct GoConstantEvaluator {
    // 76 decimal digits fit within Go's guaranteed minimum 256-bit integer precision.
    private let maximumDigits = 76

    func evaluate(_ expression: SourceExpression) throws -> GoConstant? {
        switch expression {
        case .variable, .call: return nil
        case .literal(let raw):
            if raw == "true" || raw == "false" { return .boolean(raw == "true") }
            let magnitude = raw.hasPrefix("-") ? raw.dropFirst() : raw[...]
            guard !magnitude.isEmpty, magnitude.utf8.allSatisfy({ (48...57).contains($0) }),
                  magnitude.count == 1 || magnitude.first != "0" else { throw GoConstantError.invalidLiteral }
            guard magnitude.count <= maximumDigits else { throw GoConstantError.precisionLimit }
            let value = try MathematicalInteger(raw == "-0" ? "0" : raw, maximumDigits: maximumDigits)
            return .integer(value)
        case .unary(let operation, let expression):
            guard let operand = try evaluate(expression) else { return nil }
            switch (operation, operand) {
            case ("-", .integer(let value)): return .integer(value.negated())
            case ("!", .boolean(let value)): return .boolean(!value)
            default: throw GoConstantError.typeMismatch
            }
        case .binary(let operation, let left, let right):
            if ["<", ">", "<=", ">=", "==", "!="].contains(operation) {
                for operand in [left, right] {
                    if case .binary(let inner, _, _) = operand, ["<", ">", "<=", ">=", "==", "!="].contains(inner) {
                        throw GoConstantError.nestedComparison
                    }
                }
            }
            let leftValue = try evaluate(left)
            let rightValue = try evaluate(right)
            guard let a = leftValue, let b = rightValue else { return nil }
            switch (a, b) {
            case (.integer(let a), .integer(let b)):
                let result: MathematicalInteger
                switch operation {
                case "+": result = a.adding(b)
                case "-": result = a.adding(b.negated())
                case "*": result = a.multiplied(by: b)
                case "<": return .boolean(a < b)
                case ">": return .boolean(b < a)
                case "<=": return .boolean(!(b < a))
                case ">=": return .boolean(!(a < b))
                case "==": return .boolean(a == b)
                case "!=": return .boolean(a != b)
                default: throw GoConstantError.unsupportedOperator
                }
                guard result.digitCount <= maximumDigits else { throw GoConstantError.precisionLimit }
                return .integer(result)
            case (.boolean(let a), .boolean(let b)):
                switch operation {
                case "==": return .boolean(a == b)
                case "!=": return .boolean(a != b)
                default: throw GoConstantError.typeMismatch
                }
            default: throw GoConstantError.typeMismatch
            }
        }
    }
}
