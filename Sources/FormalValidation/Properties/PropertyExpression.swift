import FormalIR

indirect enum PropertyExpression: Sendable {
    enum Kind: Sendable, Equatable { case integer, boolean }
    case integer(String)
    case boolean(Bool)
    case argument(Int, Kind)
    case result(Kind)
    case unary(String, PropertyExpression)
    case binary(String, PropertyExpression, PropertyExpression)

    var kind: Kind {
        switch self {
        case .integer: .integer
        case .boolean: .boolean
        case .argument(_, let kind), .result(let kind): kind
        case .unary(let operation, _): operation == "!" ? .boolean : .integer
        case .binary(let operation, _, _): ["+", "-", "*"].contains(operation) ? .integer : .boolean
        }
    }
    var depth: Int {
        switch self {
        case .unary(_, let value): 1 + value.depth
        case .binary(_, let left, let right): 1 + max(left.depth, right.depth)
        default: 1
        }
    }
    var constants: [String] {
        switch self {
        case .integer(let value): [value]
        case .unary("-", .integer(let value)): value == "0" ? [value] : ["-" + value]
        case .unary(_, let value): value.constants
        case .binary(_, let left, let right): left.constants + right.constants
        default: []
        }
    }

    func lean(inputs: [String], result: String) -> String {
        switch self {
        case .integer(let value): return "(\(value) : Int)"
        case .boolean(let value): return value ? "True" : "False"
        case .argument(let index, _): return inputs[index]
        case .result: return result
        case .unary(let operation, let value): return operation == "!" ? "(¬ \(value.lean(inputs: inputs, result: result)))" : "(-\(value.lean(inputs: inputs, result: result)))"
        case .binary(let operation, let left, let right):
            let a = left.lean(inputs: inputs, result: result)
            let b = right.lean(inputs: inputs, result: result)
            let symbol: String
            switch operation {
            case "&&": symbol = "∧"
            case "||": symbol = "∨"
            case "==": symbol = left.kind == .boolean ? "↔" : "="
            case "!=": return left.kind == .boolean ? "(¬ (\(a) ↔ \(b)))" : "(\(a) ≠ \(b))"
            case "<=": symbol = "≤"
            case ">=": symbol = "≥"
            default: symbol = operation
            }
            return "(\(a) \(symbol) \(b))"
        }
    }
    func tla(inputs: [String], result: String) -> String {
        switch self {
        case .integer(let value): return value
        case .boolean(let value): return value ? "TRUE" : "FALSE"
        case .argument(let index, _): return inputs[index]
        case .result: return result
        case .unary(let operation, let value): return "(\(operation == "!" ? "~" : "-")\(value.tla(inputs: inputs, result: result)))"
        case .binary(let operation, let left, let right):
            let a = left.tla(inputs: inputs, result: result)
            let b = right.tla(inputs: inputs, result: result)
            let symbol: String
            switch operation {
            case "&&": symbol = "/\\"
            case "||": symbol = "\\/"
            case "==": symbol = left.kind == .boolean ? "<=>" : "="
            case "!=": return left.kind == .boolean ? "~(\(a) <=> \(b))" : "(\(a) # \(b))"
            default: symbol = operation
            }
            return "(\(a) \(symbol) \(b))"
        }
    }
}
