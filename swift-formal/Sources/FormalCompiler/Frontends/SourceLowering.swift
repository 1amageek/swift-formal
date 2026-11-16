import FormalIR

struct SourceLowering {
    let language: SourceLanguage
    let moduleID: String
    let functions: [SourceFunction]
    var position = SourceToken(text: "", line: 1, column: 1)
    var signatures: [String: SourceFunction] = [:]
    var nextValue = 0
    var nextBlock = 0
    var blocks: [IRBlock] = []
    var instructions: [IRInstruction] = []
    var blockID = "entry"
    var parameters: [IRParameter] = []
    typealias Binding = (id: String, type: ScalarType)

    func error(_ message: String) -> SourceDiagnostic { .init(language: language, line: position.line, column: position.column, message: message) }
    mutating func fresh() -> String { defer { nextValue += 1 }; return "v\(nextValue)" }
    mutating func label() -> String { defer { nextBlock += 1 }; return "b\(nextBlock)" }
    mutating func finish() { blocks.append(.init(id: blockID, parameters: parameters, instructions: instructions)); instructions = []; parameters = [] }
    var defaultInteger: ScalarType { [.python, .typescript, .javascript].contains(language) ? .integer : .signed }

    mutating func lower() throws -> IRProgram {
        guard !moduleID.isEmpty else { throw error("Module ID is required") }
        for function in functions {
            position = function.position
            guard signatures[function.name] == nil else { throw error("Duplicate function '\(function.name)'") }
            signatures[function.name] = function
        }
        var output: [IRFunction] = []
        for function in functions {
            position = function.position
            nextValue = 0; nextBlock = 0; blocks = []; instructions = []; blockID = "entry"; parameters = []
            var environment: [String: Binding] = [:]
            for (name, type) in function.parameters {
                guard environment[name] == nil, signatures[name] == nil else { throw error("Duplicate parameter or shadowed function '\(name)'") }
                let id = fresh(); environment[name] = (id, type); parameters.append(.init(id: id, type: type.ir))
            }
            try statements(function.body, environment: environment, result: function.result)
            output.append(.init(moduleID: moduleID, symbol: function.name, result: function.result.ir, blocks: blocks))
        }
        let program = IRProgram(functions: output); try program.validate(); return program
    }
    mutating func statements(_ body: [SourceStatement], environment original: [String: Binding], result: ScalarType) throws {
        var environment = original
        for (index, statement) in body.enumerated() {
            switch statement {
            case .binding(let name, let annotation, let expression):
                guard environment[name] == nil, signatures[name] == nil else { throw error("Rebinding or shadowing '\(name)' is unsupported") }
                if annotation == nil && [.swift, .rust, .go].contains(language) && hint(expression, environment) == nil {
                    throw error("Local integer inference requires a typed operand or an explicit annotation")
                }
                let value = try expressionValue(expression, expected: annotation, environment: environment)
                environment[name] = value
            case .returned(let expression):
                guard index == body.count - 1 else { throw error("Unreachable source after return") }
                let value = try expressionValue(expression, expected: result, environment: environment)
                instructions.append(.returnValue(value.id)); finish(); return
            case .conditional(let condition, let thenBody, let elseBody):
                guard index == body.count - 1 else { throw error("Conditional branches must terminate the function") }
                let value = try expressionValue(condition, expected: .boolean, environment: environment)
                let thenID = label(); let elseID = label()
                instructions.append(.branch(condition: value.id, thenBlock: thenID, thenArguments: [], elseBlock: elseID, elseArguments: [])); finish()
                blockID = thenID; try statements(thenBody, environment: environment, result: result)
                blockID = elseID; try statements(elseBody, environment: environment, result: result); return
            }
        }
        throw error("Every path requires an explicit return")
    }
    func hint(_ expression: SourceExpression, _ environment: [String: Binding]) -> ScalarType? {
        switch expression {
        case .variable(let name): environment[name]?.type
        case .call(let name, _): signatures[name]?.result
        case .literal(let raw):
            if ["True", "False", "true", "false"].contains(raw) { .boolean }
            else if raw.hasSuffix("ULL") || raw.hasSuffix("u64") { .unsigned }
            else { nil }
        case .unary(_, let value): hint(value, environment)
        case .binary(let op, let a, let b): ["==", "!=", "<", ">", "<=", ">="].contains(op) ? .boolean : hint(a, environment) ?? hint(b, environment)
        }
    }
    mutating func expressionValue(_ expression: SourceExpression, expected: ScalarType?, environment: [String: Binding]) throws -> Binding {
        let value: Binding
        switch expression {
        case .variable(let name):
            guard let binding = environment[name] else { throw error("Unknown variable '\(name)'") }; value = binding
        case .literal(let raw): value = try literal(raw, type: expected ?? hint(expression, environment) ?? defaultInteger)
        case .call(let name, let expressions):
            guard let function = signatures[name], function.parameters.count == expressions.count else { throw error("Unknown call or argument count '\(name)'") }
            if language == .c || language == .cpp {
                guard !expressions.contains(where: \.containsCall) else { throw error("Nested calls have unspecified C/C++ argument evaluation order") }
            }
            var actual: [String] = []
            for (expression, parameter) in zip(expressions, function.parameters) {
                let argument = try expressionValue(expression, expected: parameter.1, environment: environment); actual.append(argument.id)
            }
            let reference = fresh(); instructions.append(.functionRef(destination: reference, symbol: name))
            let id = fresh(); instructions.append(.call(destination: id, callee: reference, arguments: actual)); value = (id, function.result)
        case .unary(let op, let expression):
            if op == "!" || op == "not" {
                let operand = try expressionValue(expression, expected: .boolean, environment: environment)
                value = try invert(operand)
            } else {
                let type = expected ?? hint(expression, environment) ?? defaultInteger
                guard type != .boolean, type != .unsigned else { throw error("Unary minus requires a signed or mathematical integer") }
                let zero = try literal("0", type: type, synthetic: true)
                let operand = try expressionValue(expression, expected: type, environment: environment)
                value = try binary("-", zero, operand)
            }
        case .binary(let op, let left, let right):
            if language == .c || language == .cpp {
                guard !left.containsCall, !right.containsCall else { throw error("Calls inside C/C++ operators have unspecified evaluation order") }
            }
            let comparison = ["==", "!=", "<", ">", "<=", ">="].contains(op)
            let type = hint(left, environment) ?? hint(right, environment) ?? (comparison ? defaultInteger : expected ?? defaultInteger)
            guard type != .boolean || op == "==" || op == "!=" else { throw error("Boolean arithmetic and ordering are unsupported") }
            // Comparison chains differ across languages and are outside the shared source subset.
            if comparison {
                for operand in [left, right] {
                    if case .binary(let inner, _, _) = operand, ["==", "!=", "<", ">", "<=", ">="].contains(inner) { throw error("Nested or chained comparisons are unsupported") }
                }
            }
            let a = try expressionValue(left, expected: type, environment: environment)
            let b = try expressionValue(right, expected: type, environment: environment)
            value = try binary(op, a, b)
        }
        if let expected, value.type != expected { throw error("Expression type mismatch; implicit conversions are unsupported") }
        return value
    }
    mutating func literal(_ raw: String, type: ScalarType, synthetic: Bool = false) throws -> Binding {
        let id = fresh()
        if type == .boolean {
            let allowed = language == .python ? ["False", "True"] : ["false", "true"]
            guard let bit = allowed.firstIndex(of: raw) else { throw error("Expected a Boolean literal") }
            let pattern = try BitPattern(width: 1, bits: UInt64(bit)); instructions.append(.literal(destination: id, value: pattern)); return (id, type)
        }
        var text = raw
        if !synthetic {
            switch language {
            case .javascript, .typescript:
                guard text.hasSuffix("n") else { throw error("Number literals are unsupported; use BigInt") }; text.removeLast()
            case .c, .cpp:
                let suffix = type == .unsigned ? "ULL" : "LL"
                guard text.hasSuffix(suffix) else { throw error("C/C++ integer literals require \(suffix) suffix") }; text.removeLast(suffix.count)
            case .rust:
                if text.hasSuffix("i64") || text.hasSuffix("u64") {
                    guard text.hasSuffix(type == .unsigned ? "u64" : "i64") else { throw error("Rust literal suffix type mismatch") }; text.removeLast(3)
                }
            default: break
            }
        }
        // Reject alternate bases, separators, leading-zero octal, exponentials, and suffixes.
        let magnitude = text.hasPrefix("-") ? String(text.dropFirst()) : text
        guard !magnitude.isEmpty, magnitude.utf8.allSatisfy({ (48...57).contains($0) }), magnitude.count == 1 || !magnitude.hasPrefix("0"), magnitude.count <= 1000 else { throw error("Invalid or oversized decimal literal") }
        if type == .integer {
            let integer = try MathematicalInteger(text == "-0" ? "0" : text)
            instructions.append(.integerLiteral(destination: id, value: integer))
        } else {
            if [.c, .cpp].contains(language) && text == "-9223372036854775808" { throw error("C/C++ minimum requires an in-range positive literal before unary minus") }
            let bits: UInt64
            if type == .signed { guard let signed = Int64(text) else { throw error("Signed literal is out of range") }; bits = UInt64(bitPattern: signed) }
            else { guard let unsigned = UInt64(text) else { throw error("Unsigned literal is out of range") }; bits = unsigned }
            let pattern = try BitPattern(width: 64, bits: bits); instructions.append(.literal(destination: id, value: pattern))
        }
        return (id, type)
    }
    mutating func invert(_ value: Binding) throws -> Binding {
        let one = fresh(); let pattern = try BitPattern(width: 1, bits: 1); instructions.append(.literal(destination: one, value: pattern))
        let id = fresh(); instructions.append(.binary(destination: id, operation: .xor, left: value.id, right: one)); return (id, .boolean)
    }
    mutating func binary(_ op: String, _ a: Binding, _ b: Binding) throws -> Binding {
        guard a.type == b.type else { throw error("Mixed operand types") }
        if [">", "<=", ">="].contains(op) {
            let value = try binary("<", op == ">=" ? a : b, op == ">=" ? b : a)
            return op == ">" ? value : try invert(value)
        }
        if op == "!=" { let value = try binary("==", a, b); return try invert(value) }
        let comparison = op == "<" || op == "=="
        let id = fresh()
        if a.type == .integer {
            let operation: IRIntegerOperation
            switch op { case "+": operation = .add; case "-": operation = .subtract; case "*": operation = .multiply; case "<": operation = .lessThan; case "==": operation = .equal; default: throw error("Unsupported integer operator") }
            instructions.append(.integerBinary(destination: id, operation: operation, left: a.id, right: b.id))
        } else {
            let operation: IROperation
            switch op {
            case "+": operation = a.type == .unsigned ? .unsignedAddOverflow : .signedAddOverflow
            case "-": operation = a.type == .unsigned ? .unsignedSubtractOverflow : .signedSubtractOverflow
            case "*": operation = a.type == .unsigned ? .unsignedMultiplyOverflow : .signedMultiplyOverflow
            case "<": operation = a.type == .unsigned ? .unsignedLessThan : .signedLessThan
            case "==": operation = .equal
            default: throw error("Unsupported fixed-width operator")
            }
            instructions.append(.binary(destination: id, operation: operation, left: a.id, right: b.id))
            if !comparison {
                let result = fresh(); let overflow = fresh()
                instructions.append(.extract(destination: result, source: id, index: 0))
                instructions.append(.extract(destination: overflow, source: id, index: 1))
                if language == .swift { instructions.append(.trapIf(condition: overflow, message: "integer overflow")) }
                else if language == .rust { instructions.append(.failIf(condition: overflow, kind: .panic, message: "integer overflow")) }
                else if (language == .c || language == .cpp) && a.type == .signed { instructions.append(.failIf(condition: overflow, kind: .undefinedBehavior, message: "signed integer overflow")) }
                return (result, a.type)
            }
        }
        return (id, comparison ? .boolean : a.type)
    }
}
