import FormalCore
import FormalIR

struct PropertyProofHints {
    private indirect enum Value {
        case integer(String)
        case bits(Int, String, String?)
        case aggregate([Value])
        case function(String)
    }
    private let program: IRProgram
    private var cuts: [String] = []
    private var steps = 0
    private var depth = 0

    static func derive(_ property: BoundProperty, program: IRProgram) throws -> [String] {
        var builder = Self(program: program)
        let arguments: [Value] = property.inputTypes.enumerated().map { index, type in
            switch type {
            case .integer: return .integer("a\(index)")
            case .bits(let width):
                if property.specification.inputViews[index] == .boolean { return .bits(width, "(if a\(index) then 1 else 0)", "a\(index) = true") }
                return .bits(width, "a\(index)", width == 1 ? "a\(index) = 1" : nil)
            default: preconditionFailure("Property has a nonscalar input")
            }
        }
        for index in property.specification.inputViews.indices where property.specification.inputViews[index] == .boolean {
            try builder.cut("a\(index) = true")
        }
        let result = try builder.function(property.function.symbol, arguments: arguments)
        if property.specification.resultView == .signed, case .bits(let width, let value, _) = result {
            try builder.cut("\(value) < 2 ^ \(width - 1)")
        }
        return builder.cuts
    }
    private mutating func cut(_ proposition: String) throws {
        if proposition == "True" || proposition == "False" { return }
        guard proposition.utf8.count <= 32768 else { throw exhausted("Proof hint expression exceeds 32 KiB") }
        if !cuts.contains(proposition) { cuts.append(proposition) }
        guard cuts.count <= 8 else { throw exhausted("Automatic proof requires more than eight logical case splits") }
    }
    private mutating func function(_ symbol: String, arguments: [Value]) throws -> Value {
        guard depth < 128, let function = program.functions.first(where: { $0.symbol == symbol }),
              let first = function.blocks.first, first.parameters.count == arguments.count else { throw exhausted("Unsupported symbolic call") }
        depth += 1; defer { depth -= 1 }
        let environment = Dictionary(uniqueKeysWithValues: zip(first.parameters.map(\.id), arguments))
        return try block(first.id, function: function, environment: environment)
    }
    private mutating func block(_ id: String, function: IRFunction, environment initial: [String: Value]) throws -> Value {
        guard depth < 128, let block = function.blocks.first(where: { $0.id == id }) else { throw exhausted("Unsupported symbolic control flow") }
        depth += 1; defer { depth -= 1 }
        var environment = initial
        func value(_ id: String) throws -> Value {
            guard let value = environment[id] else { throw exhausted("Unresolved symbolic SSA value") }
            return value
        }
        func actual(_ ids: [String]) throws -> [Value] { try ids.map(value) }
        func bound(_ target: String, ids: [String]) throws -> [String: Value] {
            guard let destination = function.blocks.first(where: { $0.id == target }), destination.parameters.count == ids.count else { throw exhausted("Unsupported block arguments") }
            var values = environment
            let arguments = try actual(ids)
            for (parameter, argument) in zip(destination.parameters, arguments) { values[parameter.id] = argument }
            return values
        }
        for instruction in block.instructions {
            steps += 1
            guard steps <= 4096 else { throw exhausted("Symbolic proof-hint budget exceeded") }
            let result: Value?
            switch instruction {
            case .integerLiteral(_, let literal): result = .integer("(\(literal) : Int)")
            case .literal(_, let literal): result = .bits(literal.width, String(literal.bits), literal.width == 1 ? (literal.bits == 1 ? "True" : "False") : nil)
            case .integerBinary(_, let operation, let left, let right):
                let lhs = try value(left); let rhs = try value(right)
                guard case .integer(let a) = lhs, case .integer(let b) = rhs else { throw exhausted("Unsupported integer hint") }
                switch operation {
                case .add: result = .integer("(\(a) + \(b))")
                case .subtract: result = .integer("(\(a) - \(b))")
                case .multiply: result = .integer("(\(a) * \(b))")
                case .lessThan, .equal:
                    let proposition = "\(a) \(operation == .lessThan ? "<" : "=") \(b)"
                    try cut(proposition); result = .bits(1, "(if decide (\(proposition)) then 1 else 0)", proposition)
                }
            case .binary(_, let operation, let left, let right):
                let a = try value(left); let b = try value(right)
                result = try binary(operation, left: a, right: b)
            case .aggregate(_, let ids): result = .aggregate(try actual(ids))
            case .extract(_, let source, let index):
                let sourceValue = try value(source)
                guard case .aggregate(let values) = sourceValue, values.indices.contains(index) else { throw exhausted("Unsupported symbolic aggregate") }
                result = values[index]
            case .functionRef(_, let symbol): result = .function(symbol)
            case .call(_, let callee, let ids):
                let reference = try value(callee)
                guard case .function(let symbol) = reference else { throw exhausted("Indirect symbolic calls are unsupported") }
                let arguments = try actual(ids)
                result = try self.function(symbol, arguments: arguments)
            case .trapIf(let condition, _), .failIf(let condition, _, _):
                let conditionValue = try value(condition)
                let proposition = try truth(conditionValue)
                try cut(proposition); result = nil
            case .jump(let target, let ids):
                let values = try bound(target, ids: ids)
                return try self.block(target, function: function, environment: values)
            case .branch(let condition, let left, let leftIDs, let right, let rightIDs):
                let conditionValue = try value(condition)
                let proposition = try truth(conditionValue)
                try cut(proposition)
                let aValues = try bound(left, ids: leftIDs)
                let bValues = try bound(right, ids: rightIDs)
                let a = try self.block(left, function: function, environment: aValues)
                let b = try self.block(right, function: function, environment: bValues)
                return try merge(proposition, a, b)
            case .returnValue(let id): return try value(id)
            }
            if let destination = instruction.destination, let result {
                try checkSize(result)
                environment[destination] = result
            }
        }
        throw exhausted("Missing symbolic return")
    }
    private mutating func signed(_ width: Int, _ value: String) throws -> String {
        try cut("\(value) < 2 ^ \(width - 1)")
        return "(SwiftFormal.signed \(width) \(value))"
    }
    private mutating func binary(_ operation: IROperation, left: Value, right: Value) throws -> Value {
        guard case .bits(let width, let a, let aTruth) = left, case .bits(let otherWidth, let b, let bTruth) = right, width == otherWidth else { throw exhausted("Unsupported bit hint") }
        if operation.returnsOverflow {
            let isSigned = [.signedAddOverflow, .signedSubtractOverflow, .signedMultiplyOverflow].contains(operation)
            let x = isSigned ? try signed(width, a) : "(Int.ofNat \(a))"
            let y = isSigned ? try signed(width, b) : "(Int.ofNat \(b))"
            let symbol = [.signedAddOverflow, .unsignedAddOverflow].contains(operation) ? "+" : [.signedSubtractOverflow, .unsignedSubtractOverflow].contains(operation) ? "-" : "*"
            let math = "(\(x) \(symbol) \(y))"
            let lower = isSigned ? "-(Int.ofNat (2 ^ \(width - 1)))" : "0"
            let upper = "Int.ofNat (2 ^ \(isSigned ? width - 1 : width))"
            let overflow = "\(math) < \(lower) ∨ \(math) ≥ \(upper)"
            try cut(overflow)
            return .aggregate([.bits(width, "(\(math) % Int.ofNat (2 ^ \(width))).toNat", nil), .bits(1, "(if decide (\(overflow)) then 1 else 0)", overflow)])
        }
        switch operation {
        case .signedLessThan, .unsignedLessThan, .equal:
            let x = operation == .signedLessThan ? try signed(width, a) : a
            let y = operation == .signedLessThan ? try signed(width, b) : b
            let condition = "\(x) \(operation == .equal ? "=" : "<") \(y)"
            try cut(condition)
            return .bits(1, "(if decide (\(condition)) then 1 else 0)", condition)
        case .and, .or, .xor:
            let symbol = operation == .and ? "land" : operation == .or ? "lor" : "xor"
            let proposition: String?
            if width == 1, let aTruth, let bTruth {
                proposition = operation == .and ? "(\(aTruth)) ∧ (\(bTruth))" : operation == .or ? "(\(aTruth)) ∨ (\(bTruth))" : "¬ ((\(aTruth)) ↔ (\(bTruth)))"
            } else { proposition = nil }
            return .bits(width, "(Nat.\(symbol) \(a) \(b))", proposition)
        default: throw exhausted("Unsupported binary hint")
        }
    }
    private func truth(_ value: Value) throws -> String {
        guard case .bits(1, let bits, let proposition) = value else { throw exhausted("Expected a symbolic Boolean") }
        return proposition ?? "\(bits) = 1"
    }
    private func merge(_ condition: String, _ left: Value, _ right: Value) throws -> Value {
        let value: Value
        switch (left, right) {
        case (.integer(let a), .integer(let b)): value = .integer("(if \(condition) then \(a) else \(b))")
        case (.bits(let width, let a, _), .bits(let other, let b, _)) where width == other:
            value = .bits(width, "(if \(condition) then \(a) else \(b))", nil)
        case (.aggregate(let a), .aggregate(let b)) where a.count == b.count:
            value = .aggregate(try zip(a, b).map { try merge(condition, $0.0, $0.1) })
        default: throw exhausted("Unsupported symbolic result merge")
        }
        try checkSize(value)
        return value
    }
    private func checkSize(_ value: Value) throws {
        switch value {
        case .integer(let expression), .bits(_, let expression, _):
            guard expression.utf8.count <= 32768 else { throw exhausted("Symbolic hint expression exceeds 32 KiB") }
        case .aggregate(let values): for value in values { try checkSize(value) }
        case .function: break
        }
    }
    private func exhausted(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.timeout, message) }
}
