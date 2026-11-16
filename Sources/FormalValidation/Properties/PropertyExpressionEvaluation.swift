import FormalCore
import FormalIR

extension PropertyExpression {
    func evaluate(arguments: [PropertyScalar], result: PropertyScalar?) throws -> PropertyScalar {
        switch self {
        case .integer(let value): return .integer(try MathematicalInteger(value, maximumDigits: 256))
        case .number(let bits): return .number(bits)
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
            if case .number(let bits) = value {
                if operation == "isNegativeZero" { return .boolean(bits == 0x8000000000000000) }
                guard let op = PropertyNumberOperation.unary(operation) else { throw PropertySpecification.invalid("Unknown Number predicate") }
                let actual = try Binary64.evaluate(op, bits, bits)
                return actual.boolean ? .boolean(actual.bits == 1) : .number(actual.bits)
            }
            guard case .integer(let integer) = value else { throw PropertySpecification.invalid("Expected an integer") }
            return .integer(integer.negated())
        case .binary(let operation, let left, let right):
            let a = try left.evaluate(arguments: arguments, result: result)
            let b = try right.evaluate(arguments: arguments, result: result)
            if case .number(let x) = a, case .number(let y) = b {
                guard let op = PropertyNumberOperation.binary(operation) else { throw PropertySpecification.invalid("Unknown Number expression") }
                let actual = try Binary64.evaluate(op, operation == ">" || operation == ">=" ? y : x, operation == ">" || operation == ">=" ? x : y)
                return actual.boolean ? .boolean(operation == "!=" ? actual.bits == 0 : actual.bits == 1) : .number(actual.bits)
            }
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
