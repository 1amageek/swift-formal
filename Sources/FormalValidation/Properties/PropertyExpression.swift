import FormalIR

indirect enum PropertyExpression: Sendable {
    enum Kind: Sendable, Equatable { case integer, boolean, number }
    case integer(String)
    case number(UInt64)
    case boolean(Bool)
    case argument(Int, Kind)
    case result(Kind)
    case unary(String, PropertyExpression)
    case binary(String, PropertyExpression, PropertyExpression)

    var kind: Kind {
        switch self {
        case .integer: .integer
        case .number: .number
        case .boolean: .boolean
        case .argument(_, let kind), .result(let kind): kind
        case .unary(let operation, let value): operation == "-" ? value.kind : .boolean
        case .binary(let operation, let left, _): ["+", "-", "*", "/", "%"].contains(operation) ? left.kind : .boolean
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

    var numberConstants: [UInt64] {
        switch self {
        case .number(let value): [value]
        case .unary(let operation, .number(let value)) where operation == "-": [Binary64.canonical(value ^ 0x8000000000000000)]
        case .unary(_, let value): value.numberConstants
        case .binary(_, let left, let right): left.numberConstants + right.numberConstants
        default: []
        }
    }

    func lean(inputs: [String], result: String) -> String {
        switch self {
        case .integer(let value): return "(\(value) : Int)"
        case .number(let value): return "(\(value) : Nat)"
        case .boolean(let value): return value ? "True" : "False"
        case .argument(let index, _): return inputs[index]
        case .result: return result
        case .unary(let operation, let value):
            if value.kind == .number { return PropertyNumberOperation.leanUnary(operation, value.lean(inputs: inputs, result: result)) }
            return operation == "!" ? "(¬ \(value.lean(inputs: inputs, result: result)))" : "(-\(value.lean(inputs: inputs, result: result)))"
        case .binary(let operation, let left, let right):
            let a = left.lean(inputs: inputs, result: result)
            let b = right.lean(inputs: inputs, result: result)
            if left.kind == .number { return PropertyNumberOperation.leanBinary(operation, a, b) }
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
        case .number(let value):
            let digits = (0..<64).map { String((value >> $0) & 1) }.joined(separator: ",")
            return "Bits(64,<<\(digits)>>)"
        case .boolean(let value): return value ? "TRUE" : "FALSE"
        case .argument(let index, _): return inputs[index]
        case .result: return result
        case .unary(let operation, let value):
            if value.kind == .number { return PropertyNumberOperation.tlaUnary(operation, value.tla(inputs: inputs, result: result)) }
            return "(\(operation == "!" ? "~" : "-")\(value.tla(inputs: inputs, result: result)))"
        case .binary(let operation, let left, let right):
            let a = left.tla(inputs: inputs, result: result)
            let b = right.tla(inputs: inputs, result: result)
            if left.kind == .number { return PropertyNumberOperation.tlaBinary(operation, a, b) }
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
