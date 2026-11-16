import FormalIR

struct PropertyExpressionParser {
    private let tokens: [String]
    private let inputs: [PropertyView]
    private let result: PropertyView?
    private let numberLiterals: Bool
    private var cursor = 0
    private var nesting = 0

    static func parse(_ source: String, inputs: [PropertyView], result: PropertyView?, numberLiterals: Bool = false) throws -> PropertyExpression {
        guard !source.isEmpty, source.utf8.count <= 4096 else { throw PropertySpecification.invalid("Expression must contain 1...4096 UTF-8 bytes") }
        let bytes = Array(source.utf8)
        var tokens: [String] = []; var offset = 0
        while offset < bytes.count {
            let first = bytes[offset]
            if [9, 10, 13, 32].contains(first) { offset += 1; continue }
            let start = offset
            if (48...57).contains(first) || (first == 46 && offset + 1 < bytes.count && (48...57).contains(bytes[offset+1])) {
                while offset < bytes.count && (48...57).contains(bytes[offset]) { offset += 1 }
                if offset < bytes.count && bytes[offset] == 46 {
                    offset += 1; while offset < bytes.count && (48...57).contains(bytes[offset]) { offset += 1 }
                }
                if offset < bytes.count && (bytes[offset] == 101 || bytes[offset] == 69) {
                    offset += 1
                    if offset < bytes.count && (bytes[offset] == 43 || bytes[offset] == 45) { offset += 1 }
                    while offset < bytes.count && (48...57).contains(bytes[offset]) { offset += 1 }
                }
            } else if (65...90).contains(first) || (97...122).contains(first) {
                offset += 1
                while offset < bytes.count && ((48...57).contains(bytes[offset]) || (65...90).contains(bytes[offset]) || (97...122).contains(bytes[offset])) { offset += 1 }
            } else {
                offset += 1
                if offset < bytes.count, ["&&", "||", "==", "!=", "<=", ">="].contains(String(decoding: bytes[start...offset], as: UTF8.self)) { offset += 1 }
            }
            tokens.append(String(decoding: bytes[start..<offset], as: UTF8.self))
            guard tokens.count <= 1024 else { throw PropertySpecification.invalid("Expression exceeds 1024 tokens") }
        }
        var parser = Self(tokens: tokens, inputs: inputs, result: result, numberLiterals: numberLiterals || inputs.contains(.number) || result == .number)
        let expression = try parser.expression(minimum: 0)
        guard parser.cursor == tokens.count, expression.kind == .boolean else { throw PropertySpecification.invalid("Expected a complete Boolean expression") }
        return expression
    }
    private mutating func expression(minimum: Int) throws -> PropertyExpression {
        nesting += 1; defer { nesting -= 1 }
        guard nesting <= 64 else { throw PropertySpecification.invalid("Expression nesting exceeds 64") }
        var left = try atom()
        while cursor < tokens.count, let precedence = precedence(tokens[cursor]), precedence >= minimum {
            let operation = tokens[cursor]; cursor += 1
            let right = try expression(minimum: precedence + 1)
            switch operation {
            case "+", "-", "*", "/", "%", "<", "<=", ">", ">=":
                guard left.kind == right.kind, left.kind == .integer || left.kind == .number else { throw PropertySpecification.invalid("Matching numeric operands required") }
                guard !["/", "%"].contains(operation) || left.kind == .number else { throw PropertySpecification.invalid("Division and remainder require Number views") }
            case "&&", "||":
                guard left.kind == .boolean, right.kind == .boolean else { throw PropertySpecification.invalid("Boolean operands required") }
            default:
                guard left.kind == right.kind else { throw PropertySpecification.invalid("Equality operand types differ") }
            }
            left = .binary(operation, left, right)
            guard left.depth <= 64 else { throw PropertySpecification.invalid("Expression tree depth exceeds 64") }
        }
        return left
    }
    private mutating func atom() throws -> PropertyExpression {
        guard cursor < tokens.count else { throw PropertySpecification.invalid("Missing expression operand") }
        let token = tokens[cursor]; cursor += 1
        if token == "(" {
            let value = try expression(minimum: 0)
            guard cursor < tokens.count, tokens[cursor] == ")" else { throw PropertySpecification.invalid("Missing closing parenthesis") }
            cursor += 1; return value
        }
        if token == "!" || token == "-" {
            let value = try expression(minimum: 6)
            guard token == "!" ? value.kind == .boolean : (value.kind == .integer || value.kind == .number) else { throw PropertySpecification.invalid("Unary operand type mismatch") }
            let node = PropertyExpression.unary(token, value)
            guard node.depth <= 64 else { throw PropertySpecification.invalid("Expression tree depth exceeds 64") }
            return node
        }
        if ["isNaN", "isFinite", "isInteger", "isSafeInteger", "isNegativeZero", "sameValue"].contains(token) {
            guard cursor < tokens.count, tokens[cursor] == "(" else { throw PropertySpecification.invalid("Number predicate requires parentheses") }
            cursor += 1
            let first = try expression(minimum: 0)
            guard first.kind == .number else { throw PropertySpecification.invalid("Number predicate requires a Number") }
            let node: PropertyExpression
            if token == "sameValue" {
                guard cursor < tokens.count, tokens[cursor] == "," else { throw PropertySpecification.invalid("sameValue requires two operands") }
                cursor += 1
                let second = try expression(minimum: 0)
                guard second.kind == .number else { throw PropertySpecification.invalid("sameValue requires Numbers") }
                node = .binary("sameValue", first, second)
            } else { node = .unary(token, first) }
            guard cursor < tokens.count, tokens[cursor] == ")", node.depth <= 64 else { throw PropertySpecification.invalid("Invalid Number predicate") }
            cursor += 1; return node
        }
        if token == "NaN" || token == "Infinity" { return .number(try Binary64.parse(token)) }
        if token == "true" || token == "false" { return .boolean(token == "true") }
        if token == "result" {
            guard let result else { throw PropertySpecification.invalid("requires cannot reference result") }
            return .result(result.expressionType)
        }
        if token.hasPrefix("arg"), let index = Int(token.dropFirst(3)), token == "arg\(index)", inputs.indices.contains(index) { return .argument(index, inputs[index].expressionType) }
        if token.utf8.first.map({ (48...57).contains($0) || $0 == 46 }) == true {
            if numberLiterals || token.contains(".") || token.contains("e") || token.contains("E") {
                do { return .number(try Binary64.parse(token)) }
                catch { throw PropertySpecification.invalid("Invalid Number literal") }
            }
            let integer = try MathematicalInteger(token, maximumDigits: 256)
            return .integer(integer.description)
        }
        throw PropertySpecification.invalid("Unknown expression token: \(token)")
    }
    private func precedence(_ token: String) -> Int? {
        switch token {
        case "||": 0
        case "&&": 1
        case "==", "!=": 2
        case "<", "<=", ">", ">=": 3
        case "+", "-": 4
        case "*", "/", "%": 5
        default: nil
        }
    }
}
