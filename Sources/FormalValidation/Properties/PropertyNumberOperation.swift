import FormalIR

enum PropertyNumberOperation {
    static func binary(_ name: String) -> IROperation? {
        switch name {
        case "+": .numberAdd
        case "-": .numberSubtract
        case "*": .numberMultiply
        case "/": .numberDivide
        case "%": .numberRemainder
        case "==", "!=": .numberEqual
        case "<", ">": .numberLessThan
        case "<=", ">=": .numberLessEqual
        case "sameValue": .numberSameValue
        default: nil
        }
    }
    static func unary(_ name: String) -> IROperation? {
        switch name {
        case "-": .numberNegate
        case "isNaN": .numberIsNaN
        case "isFinite": .numberIsFinite
        case "isInteger": .numberIsInteger
        case "isSafeInteger": .numberIsSafeInteger
        default: nil
        }
    }
    static func leanBinary(_ name: String, _ a: String, _ b: String) -> String {
        switch name {
        case "+", "-", "*", "/", "%":
            let op = ["+": "add", "-": "subtract", "*": "multiply", "/": "divide", "%": "remainder"][name]!
            return "(SwiftFormal.numberArithmetic .\(op) \(a) \(b))"
        case "==": return "(SwiftFormal.numberEq \(a) \(b) = true)"
        case "!=": return "(SwiftFormal.numberEq \(a) \(b) = false)"
        case "<": return "(SwiftFormal.numberLt \(a) \(b) = true)"
        case ">": return "(SwiftFormal.numberLt \(b) \(a) = true)"
        case "<=": return "((SwiftFormal.numberLt \(a) \(b) || SwiftFormal.numberEq \(a) \(b)) = true)"
        case ">=": return "((SwiftFormal.numberLt \(b) \(a) || SwiftFormal.numberEq \(a) \(b)) = true)"
        case "sameValue": return "((SwiftFormal.numberNaN \(a) = true ∧ SwiftFormal.numberNaN \(b) = true) ∨ \(a) = \(b))"
        default: preconditionFailure("Unknown typed Number expression")
        }
    }
    static func leanUnary(_ name: String, _ value: String) -> String {
        switch name {
        case "-": "(SwiftFormal.numberNeg \(value))"
        case "isNaN": "(SwiftFormal.numberNaN \(value) = true)"
        case "isFinite": "(SwiftFormal.numberFinite \(value) = true)"
        case "isInteger": "(SwiftFormal.numberInteger \(value) = true)"
        case "isSafeInteger": "(SwiftFormal.numberInteger \(value) = true ∧ SwiftFormal.numberAbs \(value) ≤ 4845873199050653695)"
        case "isNegativeZero": "(\(value) = 9223372036854775808)"
        default: preconditionFailure("Unknown typed Number predicate")
        }
    }
    static func tlaBinary(_ name: String, _ a: String, _ b: String) -> String {
        switch name {
        case "+": "FPAdd(\(a), \(b))"
        case "-": "FPAdd(\(a), FPNeg(\(b)))"
        case "*": "FPMultiply(\(a), \(b))"
        case "/": "FPQuotient(\(a), \(b))"
        case "%": "FPRem(\(a), \(b))"
        case "==": "FPEqual(\(a), \(b))"
        case "!=": "~FPEqual(\(a), \(b))"
        case "<": "FPLess(\(a), \(b))"
        case ">": "FPLess(\(b), \(a))"
        case "<=": "(FPLess(\(a), \(b)) \\/ FPEqual(\(a), \(b)))"
        case ">=": "(FPLess(\(b), \(a)) \\/ FPEqual(\(a), \(b)))"
        case "sameValue": "((FPNaN(\(a)) /\\ FPNaN(\(b))) \\/ \(a).bits = \(b).bits)"
        default: preconditionFailure("Unknown typed Number expression")
        }
    }
    static func tlaUnary(_ name: String, _ value: String) -> String {
        switch name {
        case "-": "FPNeg(\(value))"
        case "isNaN": "FPNaN(\(value))"
        case "isFinite": "FPFinite(\(value))"
        case "isInteger": "FPInteger(\(value))"
        case "isSafeInteger": "(NumberBinary(\"numberIsSafeInteger\", \(value), \(value)).bits = <<1>>)"
        case "isNegativeZero": "(\(value).bits = FPZeroValue(1).bits)"
        default: preconditionFailure("Unknown typed Number predicate")
        }
    }
}
