import Foundation

/// One independently modeled syntax site. Inputs assume standard 64-bit Swift integer operators.
public struct SwiftExpressionSite: Sendable {
    public enum Operand: Sendable {
        case integer(Int64), scalar, count

        var bounds: ClosedRange<Int64> {
            switch self {
            case .integer(let value): value...value
            case .scalar: Int64.min...Int64.max
            case .count: 0...Int64.max
            }
        }
        var label: String {
            switch self {
            case .integer(let n): String(n)
            case .scalar: "Int64 input"
            case .count: "Collection count"
            }
        }
        func term(_ parameter: String, lean: Bool) -> String {
            if case .integer(let n) = self { return lean ? "(\(n) : Int)" : n < 0 ? "(\(n))" : String(n) }
            return parameter
        }
    }
    public enum Operation: String, Sendable {
        case add = "+", subtract = "-", multiply = "*", divide = "/", remainder = "%"
        func evaluate(_ lhs: Int64, _ rhs: Int64) -> Bool {
            switch self {
            case .add: !lhs.addingReportingOverflow(rhs).overflow
            case .subtract: !lhs.subtractingReportingOverflow(rhs).overflow
            case .multiply: !lhs.multipliedReportingOverflow(by: rhs).overflow
            case .divide, .remainder: rhs != 0 && !(lhs == .min && rhs == -1)
            }
        }
    }
    public enum Comparison: String, Sendable {
        case equal = "==", different = "!=", less = "<", atMost = "<=", greater = ">", atLeast = ">="
        func symbol(lean: Bool) -> String {
            switch self {
            case .equal: "="
            case .different: lean ? "≠" : "#"
            case .atMost: lean ? "≤" : "<="
            case .atLeast: lean ? "≥" : ">="
            case .less, .greater: rawValue
            }
        }
    }
    public enum Predicate: Sendable {
        case comparison(Operand, Comparison, Operand)
        case opaque
    }
    public enum Expression: Sendable {
        case arithmetic(Operand, Operation, Operand)
        case conditional(isGuard: Bool, predicate: Predicate)
    }
    public let bytes: Range<Int>
    public let expression: Expression
    public init(bytes: Range<Int>, expression: Expression) { self.bytes = bytes; self.expression = expression }

    /// Addition, subtraction and multiplication attain their extrema at rectangle corners.
    /// Signed division and remainder have exactly two exceptional operand patterns.
    public var localCheck: String {
        guard case .arithmetic(let lhs, let op, let rhs) = expression else {
            if case .conditional(_, .comparison) = expression { return "Integer comparison modeled" }
            return "Predicate abstracted"
        }
        let a = lhs.bounds, b = rhs.bounds
        if op == .divide || op == .remainder {
            if b == 0...0 { return "Always traps" }
            if b.contains(0) || (a.contains(.min) && b.contains(-1)) {
                return a == Int64.min...Int64.min && b == -1 ... -1 ? "Always traps" : "Possible trap"
            }
        } else if ![a.lowerBound, a.upperBound].allSatisfy({ x in
            [b.lowerBound, b.upperBound].allSatisfy { op.evaluate(x, $0) }
        }) {
            return a.lowerBound == a.upperBound && b.lowerBound == b.upperBound ? "Always traps" : "Possible trap"
        }
        return "No arithmetic trap"
    }

    /// Returns a single definition, with the operand domain and exceptional result encoded.
    func definition(_ name: String, lean: Bool) -> String {
        func signature(_ lhs: Operand, _ rhs: Operand) -> String {
            let parameters = [(lhs,"a"),(rhs,"b")].compactMap { operand, symbol -> String? in
                if case .integer = operand { return nil }
                return symbol
            }
            guard !parameters.isEmpty else { return name }
            return lean ? name + " (" + parameters.joined(separator: " ") + " : Int)" : name + "(" + parameters.joined(separator: ",") + ")"
        }
        guard case .arithmetic(let lhs, let op, let rhs) = expression else {
            if case .conditional(_, .comparison(let lhs, let op, let rhs)) = expression {
                let test = lhs.term("a", lean: lean) + " " + op.symbol(lean: lean) + " " + rhs.term("b", lean: lean)
                return lean ? "def \(signature(lhs,rhs)) : Bool := decide (\(test))\n" : "\(signature(lhs,rhs)) == \(test)\n"
            }
            return lean ? "def \(name) (condition : Bool) : Bool := if condition then true else false\n"
                : "\(name)(condition) == IF condition THEN TRUE ELSE FALSE\n"
        }
        let x = lhs.term("a", lean: lean), y = rhs.term("b", lean: lean)
        let min = String(Int64.min), max = String(Int64.max)
        let div = op == .divide || op == .remainder
        var checks = [(lhs,x), (rhs,y)].map { operand, term in
            lean ? "(\(operand.bounds.lowerBound) ≤ \(term) ∧ \(term) ≤ \(operand.bounds.upperBound))"
                 : "(\(term) \\in \(operand.bounds.lowerBound)..\(operand.bounds.upperBound))"
        }
        if div {
            checks.append(lean ? "(\(y) ≠ 0 ∧ ¬ (\(x) = \(min) ∧ \(y) = -1))"
                               : "(\(y) # 0 /\\ ~(\(x) = \(min) /\\ \(y) = -1))")
        }
        let arithmetic: String
        switch op {
        case .divide: arithmetic = lean ? "Int.tdiv \(x) \(y)" : "Quot(\(x), \(y))"
        case .remainder: arithmetic = lean ? "Int.tmod \(x) \(y)" : "(\(x) - \(y) * Quot(\(x), \(y)))"
        default: arithmetic = "(\(x) \(op.rawValue) \(y))"
        }
        if !div {
            checks.append(lean ? "(\(min) ≤ \(arithmetic) ∧ \(arithmetic) ≤ \(max))" : "(\(arithmetic) \\in \(min)..\(max))")
        }
        if lean { return "def \(signature(lhs,rhs)) : Option Int := if \(checks.joined(separator: " ∧ ")) then some (\(arithmetic)) else none\n" }
        return "\(signature(lhs,rhs)) == IF \(checks.joined(separator: " /\\ ")) THEN <<\(arithmetic)>> ELSE <<>>\n"
    }
}
