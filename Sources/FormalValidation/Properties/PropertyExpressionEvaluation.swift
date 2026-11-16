import FormalCore
import FormalIR

extension PropertyExpression {
    func evaluate(arguments: [PropertyScalar], result: PropertyScalar?) throws -> PropertyScalar {
        switch self {
        case .integer(let value): return .integer(try MathematicalInteger(value, maximumDigits: 256))
        case .boolean(let value): return .boolean(value)
        case .argument(let index, _): return arguments[index]
        case .result:
            guard let result else { throw PropertySpecification.invalid("Result is unavailable") }
            return result
        case .unary(let operation, let expression):
            let value = try expression.evaluate(arguments: arguments, result: result)
            if operation == "!" {
                let boolean = try value.boolean
                return .boolean(!boolean)
            }
            guard case .integer(let integer) = value else { throw PropertySpecification.invalid("Expected an integer") }
            return .integer(integer.negated())
        case .binary(let operation, let left, let right):
            let a = try left.evaluate(arguments: arguments, result: result)
            let b = try right.evaluate(arguments: arguments, result: result)
            if operation == "==" { return .boolean(a == b) }
            if operation == "!=" { return .boolean(a != b) }
            if operation == "&&" || operation == "||" {
                let x = try a.boolean; let y = try b.boolean
                return .boolean(operation == "&&" ? x && y : x || y)
            }
            guard case .integer(let x) = a, case .integer(let y) = b else { throw PropertySpecification.invalid("Expected integer operands") }
            switch operation {
            case "<": return .boolean(x < y)
            case "<=": return .boolean(x <= y)
            case ">": return .boolean(x > y)
            case ">=": return .boolean(x >= y)
            default:
                guard x.digitCount + y.digitCount <= 4096 else { throw FormalDiagnostic(.timeout, "Property witness arithmetic budget exceeded") }
                let value: MathematicalInteger
                if operation == "+" { value = x.adding(y) }
                else if operation == "-" { value = x.adding(y.negated()) }
                else { value = x.multiplied(by: y) }
                return .integer(value)
            }
        }
    }
}
