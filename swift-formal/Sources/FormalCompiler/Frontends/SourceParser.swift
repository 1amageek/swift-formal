struct SourceParser {
    let language: SourceLanguage
    let tokens: [SourceToken]
    var cursor = 0
    var nesting = 0
    typealias ParsedExpression = (value: SourceExpression, depth: Int)
    let maximumNesting: Int
    private static let reserved: Set<String> = ["return", "if", "else", "func", "fn", "def", "function", "let", "const", "var", "mut", "pub", "public", "export", "async", "await", "true", "false", "True", "False", "package", "import", "class", "struct", "while", "for", "switch", "match", "int", "bool", "int64", "uint64", "i64", "u64", "Int64", "UInt64", "Bool", "bigint", "boolean", "int64_t", "uint64_t", "not", "and", "or", "None", "null", "undefined"]
    private static let keywords = Set("and_eq bitand bitor compl concept co_await co_return co_yield const_cast decltype dynamic_cast not_eq nullptr reinterpret_cast static_cast wchar_t char8_t char16_t char32_t xor xor_eq _Atomic _Alignas _Alignof _Bool _Complex _Generic _Imaginary _Noreturn _Static_assert _Thread_local crate dyn move mod impl box become priv unsized macro associatedtype deinit extension fileprivate inout precedencegroup subscript chan map type _ as assert async await auto break case catch char consteval constexpr constinit continue default defer delete do double elif enum except explicit extern extends final finally float for friend from global goto implements import in inline instanceof interface is lambda long match module namespace new nonlocal operator override pass private protected protocol raise range register repeat requires restrict select short signed sizeof static static_assert struct super switch template this thread_local throw throws trait try typedef type typename typeof union unsafe unsigned use using virtual void volatile when where with yield abstract boolean byte debugger del dynamic fallthrough false get init internal nil nonmutating open out readonly ref rethrows self Self set some synchronized then transient true typealias typeof unless val weak yield".split(separator: " ").map(String.init))
    var text: String { tokens[cursor].text }
    func error(_ message: String) -> SourceDiagnostic {
        .init(language: language, line: tokens[cursor].line, column: tokens[cursor].column, message: message)
    }
    mutating func take(_ value: String) -> Bool {
        if text == value { cursor += 1; return true }; return false
    }
    mutating func expect(_ value: String) throws {
        guard take(value) else { throw error("Expected '\(value)', found '\(text)'") }
    }
    mutating func lines() { while take("\n") {} }
    mutating func identifier() throws -> String {
        let name = text
        guard !Self.keywords.contains(name), let first = name.utf8.first, (65...90).contains(first) || (97...122).contains(first) || first == 95,
              !Self.reserved.contains(name) else { throw error("Expected an unreserved identifier") }
        cursor += 1; return name
    }
    mutating func type() throws -> ScalarType {
        let qualified = language == .cpp && take("std")
        if qualified { try expect("::")
            guard ["int64_t", "uint64_t"].contains(text) else { throw error("Only integer types may be std-qualified") }
        }
        guard text != "<eof>" else { throw error("Expected a scalar type") }
        let name = text; cursor += 1
        let signed: String; let unsigned: String; let boolean: String
        switch language {
        case .swift: signed = "Int64"; unsigned = "UInt64"; boolean = "Bool"
        case .rust: signed = "i64"; unsigned = "u64"; boolean = "bool"
        case .c, .cpp: signed = "int64_t"; unsigned = "uint64_t"; boolean = "bool"
        case .go: signed = "int64"; unsigned = "uint64"; boolean = "bool"
        case .python: signed = "int"; unsigned = ""; boolean = "bool"
        case .typescript: signed = "bigint"; unsigned = ""; boolean = "boolean"
        case .javascript: throw error("JavaScript type annotations are unsupported")
        }
        if name == boolean { return .boolean }
        if name == signed { return language == .python || language == .typescript ? .integer : .signed }
        if name == unsigned { return .unsigned }
        throw error("Unsupported source type '\(name)'")
    }
    mutating func parse() throws -> [SourceFunction] {
        var functions: [SourceFunction] = []; lines()
        if language == .go { try expect("package"); _ = try identifier(); try endStatement(); lines() }
        while text != "<eof>" {
            functions.append(try function())
            if language == .go || language == .swift {
                guard text == "\n" || text == "<eof>" || take(";") else { throw error("Function declarations require a statement boundary") }
            }
            lines()
        }
        guard !functions.isEmpty else { throw error("Source contains no functions") }
        return functions
    }
    mutating func function() throws -> SourceFunction {
        let position = tokens[cursor]
        let resultFirst: ScalarType?
        switch language {
        case .swift: _ = take("public"); try expect("func"); resultFirst = nil
        case .rust: _ = take("pub"); try expect("fn"); resultFirst = nil
        case .go: try expect("func"); resultFirst = nil
        case .python: try expect("def"); resultFirst = nil
        case .typescript, .javascript: _ = take("export"); try expect("function"); resultFirst = nil
        case .c, .cpp: resultFirst = try type()
        }
        let name = try identifier()
        if [.c, .cpp, .go].contains(language) && name == "main" { throw error("The process entry point is outside the pure-function profile") }
        try expect("(")
        var parameters: [(String, ScalarType)] = []
        if !take(")") {
            repeat {
                let name: String; let kind: ScalarType
                if language == .c || language == .cpp { kind = try type(); name = try identifier() }
                else {
                    if language == .swift { try expect("_") }
                    name = try identifier()
                    if language == .javascript { kind = .integer }
                    else { if language != .go { try expect(":") }; kind = try type() }
                }
                parameters.append((name, kind))
            } while take(",")
            try expect(")")
        }
        let result: ScalarType
        if let resultFirst { result = resultFirst }
        else if language == .javascript { result = .integer }
        else {
            if language == .typescript { try expect(":") }
            else if language != .go { try expect("->") }
            result = try type()
        }
        let body = try block()
        return .init(position: position, name: name, parameters: parameters, result: result, body: body)
    }
    mutating func block() throws -> [SourceStatement] {
        nesting += 1; defer { nesting -= 1 }
        guard nesting <= maximumNesting else { throw error("Syntax nesting limit exceeded") }
        let end: String
        if language == .python {
            try expect(":"); try expect("\n"); lines(); try expect("<indent>"); end = "<dedent>"
        } else { try expect("{"); end = "}" }
        var statements: [SourceStatement] = []; lines()
        while !take(end) {
            guard text != "<eof>" else { throw error("Unterminated block") }
            statements.append(try statement()); lines()
        }
        return statements
    }
    mutating func endStatement() throws {
        if language == .c || language == .cpp || language == .rust || language == .typescript || language == .javascript {
            try expect(";"); return
        }
        if take(";") { return }
        if text == "}" || text == "<dedent>" || text == "<eof>" { return }
        try expect("\n")
    }
    mutating func statement() throws -> SourceStatement {
        if take("return") { let value = try expression(); try endStatement(); return .returned(value.value) }
        if take("if") {
            let condition: SourceExpression
            if language == .c || language == .cpp || language == .typescript || language == .javascript {
                try expect("("); condition = try expression().value; try expect(")")
            } else { condition = try expression().value }
            let thenBody = try block()
            if language == .go && text == "\n" { throw error("Go else must follow the closing brace on the same line") }
            lines(); try expect("else"); let elseBody = try block()
            return .conditional(condition, thenBody, elseBody)
        }
        let name: String; var kind: ScalarType?
        switch language {
        case .swift, .rust:
            try expect("let"); name = try identifier(); if take(":") { kind = try type() }; try expect("=")
        case .typescript, .javascript:
            try expect("const"); name = try identifier()
            if language == .typescript && take(":") { kind = try type() }; try expect("=")
        case .c, .cpp:
            try expect("const"); kind = try type(); name = try identifier(); try expect("=")
        case .go: name = try identifier(); try expect(":=")
        case .python: name = try identifier(); if take(":") { kind = try type() }; try expect("=")
        }
        let value = try expression(); try endStatement(); return .binding(name, kind, value.value)
    }
    func precedence(_ op: String) -> Int {
        switch op {
        case "==", "!=": 1
        case "<", ">", "<=", ">=": 2
        case "+", "-": 3
        case "*": 4
        default: -1
        }
    }
    func checkedDepth(_ depth: Int) throws -> Int {
        guard depth <= maximumNesting else { throw error("Expression tree depth limit exceeded") }
        return depth
    }
    mutating func expression(_ minimum: Int = 0) throws -> ParsedExpression {
        nesting += 1; defer { nesting -= 1 }
        guard nesting <= maximumNesting else { throw error("Expression nesting limit exceeded") }
        var left = try primary()
        var chainLength = 0
        while precedence(text) >= minimum {
            chainLength += 1
            guard chainLength <= maximumNesting else { throw error("Expression chain limit exceeded") }
            let op = text; cursor += 1
            let right = try expression(precedence(op) + 1)
            let depth = try checkedDepth(1 + max(left.depth, right.depth))
            left = (.binary(op, left.value, right.value), depth)
        }
        return left
    }
    mutating func primary() throws -> ParsedExpression {
        if take("(") { let value = try expression(); try expect(")"); return value }
        if text == "-" || (text == "!" && language != .python) || (text == "not" && language == .python) {
            let op = text; cursor += 1
            let value = try expression(op == "not" ? 1 : 5)
            if op == "-", case .literal(let literal) = value.value { return (.literal("-" + literal), 1) }
            let depth = try checkedDepth(value.depth + 1)
            return (.unary(op, value.value), depth)
        }
        let value = text
        if let first = value.utf8.first, (48...57).contains(first) { cursor += 1; return (.literal(value), 1) }
        let bools = language == .python ? ["True", "False"] : ["true", "false"]
        if bools.contains(value) { cursor += 1; return (.literal(value), 1) }
        let name = try identifier()
        if take("(") {
            var arguments: [SourceExpression] = []
            var deepestArgument = 0
            if !take(")") {
                repeat {
                    let argument = try expression()
                    deepestArgument = max(deepestArgument, argument.depth)
                    arguments.append(argument.value)
                } while take(",")
                try expect(")")
            }
            let depth = try checkedDepth(1 + deepestArgument)
            return (.call(name, arguments), depth)
        }
        return (.variable(name), 1)
    }
}
