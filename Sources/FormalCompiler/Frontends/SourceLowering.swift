import FormalIR

struct SourceLowering {
    let language: SourceLanguage
    let moduleID: String
    let functions: [SourceFunction]
    var position = SourceToken(text: "", line: 1, column: 1)
    var signatures: [String: SourceFunction] = [:]
    var visibleFunctions: Set<String> = []
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
    var defaultInteger: ScalarType { [.python, .typescript, .javascript, .bun].contains(language) ? .integer : language == .java ? .signed32 : .signed }

    mutating func lower() throws -> IRProgram {
        guard !moduleID.isEmpty else { throw error("Module ID is required") }
        for function in functions {
            position = function.position
            guard signatures[function.name] == nil else { throw error("Duplicate function '\(function.name)'") }
            signatures[function.name] = function
        }
        visibleFunctions = [.c, .cpp].contains(language) ? [] : Set(signatures.keys)
        var output: [IRFunction] = []
        for function in functions {
            position = function.position
            visibleFunctions.insert(function.name)
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
        var pending = [expression]
        while let expression = pending.popLast() {
            switch expression {
            case .variable(let name): if let type = environment[name]?.type { return type }
            case .call(let name, _): if let type = signatures[name]?.result { return type }
            case .literal(let raw):
                if ["True", "False", "true", "false"].contains(raw) { return .boolean }
                if language == .java { return raw.hasSuffix("L") || raw.hasSuffix("l") ? .signed : .signed32 }
                if raw.hasSuffix("ULL") || raw.hasSuffix("u64") { return .unsigned }
            case .unary(_, let value): pending.append(value)
            case .binary(let operation, let left, let right):
                if isComparison(operation) { return .boolean }
                pending.append(right); pending.append(left)
            }
        }
        return nil
    }
    private func isComparison(_ operation: String) -> Bool {
        ["==", "!=", "<", ">", "<=", ">="].contains(operation)
    }
    private func checked(_ value: Binding, expected: ScalarType?) throws -> Binding {
        if let expected, value.type != expected { throw error("Expression type mismatch; implicit conversions are unsupported") }
        return value
    }
    private mutating func constantValue(_ expression: SourceExpression, expected: ScalarType?) throws -> Binding? {
        guard language == .go else { return nil }
        let constant: GoConstant?
        do { constant = try GoConstantEvaluator().evaluate(expression) }
        catch let failure as GoConstantError { throw error(failure.description) }
        guard let constant else { return nil }
        switch constant {
        case .integer(let integer):
            let type = expected ?? defaultInteger
            guard type == .signed || type == .unsigned else { throw error("Go integer constant cannot convert to this type") }
            return try literal(integer.description, type: type)
        case .boolean(let boolean):
            guard expected == nil || expected == .boolean else { throw error("Go Boolean constant cannot convert to this type") }
            return try literal(boolean ? "true" : "false", type: .boolean)
        }
    }
    private enum ExpressionWork {
        case evaluate(SourceExpression, ScalarType?)
        case invert(ScalarType?)
        case negate(Binding, ScalarType?)
        case binary(String, ScalarType?)
        case call(String, Int, ScalarType?)
    }
    mutating func expressionValue(_ expression: SourceExpression, expected: ScalarType?, environment: [String: Binding]) throws -> Binding {
        var pending: [ExpressionWork] = [.evaluate(expression, expected)]
        var values: [Binding] = []
        while let work = pending.popLast() {
            switch work {
            case .evaluate(let expression, let expected):
                if let constant = try constantValue(expression, expected: expected) { values.append(constant); continue }
                switch expression {
                case .variable(let name):
                    guard let value = environment[name] else { throw error("Unknown variable '\(name)'") }
                    values.append(try checked(value, expected: expected))
                case .literal(let raw):
                    let value = try literal(raw, type: expected ?? hint(expression, environment) ?? defaultInteger)
                    values.append(try checked(value, expected: expected))
                case .call(let name, let expressions):
                    guard visibleFunctions.contains(name) else { throw error("Call to '\(name)' precedes its declaration or is unresolved") }
                    guard let function = signatures[name], function.parameters.count == expressions.count else { throw error("Unknown call or argument count '\(name)'") }
                    if language == .c || language == .cpp {
                        guard !expressions.contains(where: \.containsCall) else { throw error("Nested calls have unspecified C/C++ argument evaluation order") }
                    }
                    pending.append(.call(name, expressions.count, expected))
                    for (argument, parameter) in zip(expressions, function.parameters).reversed() {
                        pending.append(.evaluate(argument, parameter.1))
                    }
                case .unary(let operation, let operand):
                    if operation == "!" || operation == "not" {
                        pending.append(.invert(expected)); pending.append(.evaluate(operand, .boolean))
                    } else {
                        let type = expected ?? hint(operand, environment) ?? defaultInteger
                        guard type != .boolean, type != .unsigned else { throw error("Unary minus requires a signed or mathematical integer") }
                        let zero = try literal("0", type: type, synthetic: true)
                        pending.append(.negate(zero, expected)); pending.append(.evaluate(operand, type))
                    }
                case .binary(let operation, let left, let right):
                    if language == .c || language == .cpp {
                        guard !left.containsCall, !right.containsCall else { throw error("Calls inside C/C++ operators have unspecified evaluation order") }
                    }
                    let comparison = isComparison(operation)
                    let type = hint(left, environment) ?? hint(right, environment) ?? (comparison ? defaultInteger : expected ?? defaultInteger)
                    guard type != .boolean || operation == "==" || operation == "!=" else { throw error("Boolean arithmetic and ordering are unsupported") }
                    if comparison {
                        for operand in [left, right] {
                            if case .binary(let inner, _, _) = operand, isComparison(inner) { throw error("Nested or chained comparisons are unsupported") }
                        }
                    }
                    pending.append(.binary(operation, expected))
                    pending.append(.evaluate(right, type)); pending.append(.evaluate(left, type))
                }
            case .invert(let expected):
                guard let operand = values.popLast() else { throw error("Missing unary operand") }
                let value = try invert(operand)
                values.append(try checked(value, expected: expected))
            case .negate(let zero, let expected):
                guard let operand = values.popLast() else { throw error("Missing unary operand") }
                let value = try binary("-", zero, operand)
                values.append(try checked(value, expected: expected))
            case .binary(let operation, let expected):
                guard let right = values.popLast(), let left = values.popLast() else { throw error("Missing binary operand") }
                let value = try binary(operation, left, right)
                values.append(try checked(value, expected: expected))
            case .call(let name, let count, let expected):
                guard let function = signatures[name], values.count >= count else { throw error("Missing call arguments") }
                let arguments = values.suffix(count).map(\.id)
                values.removeLast(count)
                let reference = fresh(); instructions.append(.functionRef(destination: reference, symbol: name))
                let id = fresh(); instructions.append(.call(destination: id, callee: reference, arguments: arguments))
                values.append(try checked((id, function.result), expected: expected))
            }
        }
        guard values.count == 1, let value = values.first else { throw error("Invalid expression evaluation stack") }
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
            case .javascript, .typescript, .bun:
                guard text.hasSuffix("n") else { throw error("Number literals are unsupported; use BigInt") }; text.removeLast()
            case .c, .cpp:
                let suffix = type == .unsigned ? "ULL" : "LL"
                guard text.hasSuffix(suffix) else { throw error("C/C++ integer literals require \(suffix) suffix") }; text.removeLast(suffix.count)
            case .java:
                let isLong = text.hasSuffix("L") || text.hasSuffix("l")
                guard type == (isLong ? .signed : .signed32) else { throw error("Java literal width mismatch; implicit int/long conversions are outside this profile") }
                if isLong { text.removeLast() }
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
            if type == .signed32 {
                guard let signed = Int32(text) else { throw error("Java int literal is out of range") }
                bits = UInt64(UInt32(bitPattern: signed))
            }
            else if type == .signed { guard let signed = Int64(text) else { throw error("Signed literal is out of range") }; bits = UInt64(bitPattern: signed) }
            else { guard let unsigned = UInt64(text) else { throw error("Unsigned literal is out of range") }; bits = unsigned }
            let pattern = try BitPattern(width: type == .signed32 ? 32 : 64, bits: bits); instructions.append(.literal(destination: id, value: pattern))
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
