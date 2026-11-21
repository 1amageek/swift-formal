import FormalCore

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
        guard !(language == .java && ["native", "strictfp"].contains(name)), !Self.keywords.contains(name), let first = name.utf8.first, (65...90).contains(first) || (97...122).contains(first) || first == 95,
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
        case .java:
            if name == "int" { return .signed32 }
            signed = "long"; unsigned = ""; boolean = "boolean"
        case .typescript, .bun:
            if name == "number" { return .number }
            signed = "bigint"; unsigned = ""; boolean = "boolean"
        case .javascript: throw error("JavaScript type annotations are unsupported")
        }
        if name == boolean { return .boolean }
        if name == signed { return [.python, .typescript, .bun].contains(language) ? .integer : .signed }
        if name == unsigned { return .unsigned }
        if language == .swift, name == "(" || ["some", "any", "Self"].contains(name) ||
            (!Self.reserved.contains(name) && !Self.keywords.contains(name) && name.utf8.first.map({ (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }) == true) {
            let position = tokens[cursor - 1]
            throw FormalDiagnostic(.unsupportedSourceProfile, "swift:\(position.line):\(position.column): Type '\(name)' is outside the whole-function \(language.profile) profile")
        }
        throw error("Unsupported source type '\(name)'")
    }
    mutating func parse() throws -> [ParsedSourceFunction] {
        var functions: [ParsedSourceFunction] = []; lines()
        if language == .java {
            _ = take("public"); _ = take("final"); try expect("class")
            let className = try identifier()
            guard !["record", "sealed", "permits"].contains(className) else { throw error("Restricted Java type name") }
            try expect("{"); lines()
            while !take("}") {
                guard text != "<eof>" else { throw error("Unterminated Java class") }
                functions.append(try function()); lines()
            }
            lines(); try expect("<eof>")
            guard !functions.isEmpty else { throw error("Java class contains no static methods") }
            return functions
        }
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
    mutating func function() throws -> ParsedSourceFunction {
        let position = tokens[cursor]
        let resultFirst: ScalarType?
        switch language {
        case .swift:
            _ = take("public")
            if ["import","struct","class","enum","extension","actor","protocol","var","let"].contains(text) {
                throw FormalDiagnostic(.unsupportedSourceProfile, "swift:\(tokens[cursor].line):\(tokens[cursor].column): '\(text)' declarations are outside the \(language.profile) profile")
            }
            try expect("func"); resultFirst = nil
        case .rust: _ = take("pub"); try expect("fn"); resultFirst = nil
        case .go: try expect("func"); resultFirst = nil
        case .python: try expect("def"); resultFirst = nil
        case .typescript, .javascript, .bun: _ = take("export"); try expect("function"); resultFirst = nil
        case .java:
            if ["public", "private", "protected"].contains(text) { cursor += 1 }
            try expect("static"); resultFirst = try type()
        case .c, .cpp: resultFirst = try type()
        }
        let name = try identifier()
        if [.c, .cpp, .go].contains(language) && name == "main" { throw error("The process entry point is outside the pure-function profile") }
        try expect("(")
        var parameters: [(String, ScalarType?)] = []
        if !take(")") {
            repeat {
                let name: String; let kind: ScalarType?
                if [.c, .cpp, .java].contains(language) { kind = try type(); name = try identifier() }
                else {
                    if language == .swift { try expect("_") }
                    name = try identifier()
                    if language == .javascript || (language.isJavaScriptFamily && text != ":") { kind = nil }
                    else { if language != .go { try expect(":") }; kind = try type() }
                }
                parameters.append((name, kind))
            } while take(",")
            try expect(")")
        }
        if language == .java {
            let zeroArgumentConflict = parameters.isEmpty && ["getClass", "hashCode", "toString", "clone", "finalize", "notify", "notifyAll", "wait"].contains(name)
            let types = parameters.map { $0.1 }
            let waitConflict = name == "wait" && (types == [.signed] || types == [.signed, .signed32])
            guard !zeroArgumentConflict, !waitConflict else { throw error("Static signature conflicts with an inherited Java Object method") }
        }
        let result: ScalarType?
        if let resultFirst { result = resultFirst }
        else if language == .javascript || (language.isJavaScriptFamily && text != ":") { result = nil }
        else {
            if language == .typescript || language == .bun { try expect(":") }
            else if language != .go { try expect("->") }
            result = try type()
        }
        let body = try block()
        return .init(position: position, range: SourceByteRange(start: position.startByte, end: tokens[max(0,cursor-1)].endByte), name: name, parameters: parameters, result: result, body: body)
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
        if language.isJavaScriptFamily {
            if take(";") || text == "\n" || text == "}" || text == "<eof>" { return }
            throw error("Expected a statement boundary")
        }
        if [.c, .cpp, .rust, .java].contains(language) {
            try expect(";"); return
        }
        if take(";") { return }
        if text == "}" || text == "<dedent>" || text == "<eof>" { return }
        try expect("\n")
    }
    mutating func statement() throws -> SourceStatement {
        let start = tokens[cursor].startByte
        func located(_ value: SourceStatement, end: Int) -> SourceStatement { value.located(start, end) }
        if take("return") { let value = try expression(); try endStatement(); return located(.returned(value.value), end: tokens[max(0,cursor-1)].endByte) }
        if take("if") {
            let condition: SourceExpression
            if [.c, .cpp, .typescript, .javascript, .java, .bun].contains(language) {
                try expect("("); condition = try expression().value; try expect(")")
            } else { condition = try expression().value }
            let thenBody = try block()
            if language == .go && text == "\n" { throw error("Go else must follow the closing brace on the same line") }
            lines(); try expect("else"); let elseBody = try block()
            return located(.conditional(condition, thenBody, elseBody), end: tokens[max(0,cursor-1)].endByte)
        }
        let name: String; var kind: ScalarType?
        switch language {
        case .swift, .rust:
            try expect("let"); name = try identifier(); if take(":") { kind = try type() }; try expect("=")
        case .typescript, .javascript, .bun:
            if language.isJavaScriptFamily && take("let") {} else { try expect("const") }; name = try identifier()
            if (language == .typescript || language == .bun) && take(":") { kind = try type() }; try expect("=")
        case .java:
            try expect("final"); kind = try type(); name = try identifier(); try expect("=")
        case .c, .cpp:
            try expect("const"); kind = try type(); name = try identifier(); try expect("=")
        case .go: name = try identifier(); try expect(":=")
        case .python: name = try identifier(); if take(":") { kind = try type() }; try expect("=")
        }
        let value = try expression(); try endStatement(); return located(.binding(name, kind, value.value), end: tokens[max(0,cursor-1)].endByte)
    }
    func precedence(_ op: String) -> Int {
        switch op {
        case "||": 0
        case "&&": 1
        case "==", "!=", "===", "!==": 2
        case "<", ">", "<=", ">=": 3
        case "+", "-": 4
        case "*", "/", "%": 5
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
        let start = tokens[cursor].startByte
        var left = try primary()
        var chainLength = 0
        while precedence(text) >= minimum {
            chainLength += 1
            guard chainLength <= maximumNesting else { throw error("Expression chain limit exceeded") }
            let op = text; cursor += 1
            let right = try expression(precedence(op) + 1)
            let depth = try checkedDepth(1 + max(left.depth, right.depth))
            left = (SourceExpression.binary(op, left.value, right.value).located(start, tokens[max(0,cursor-1)].endByte), depth)
        }
        return left
    }
    mutating func primary() throws -> ParsedExpression {
        let start = tokens[cursor].startByte
        func located(_ value: SourceExpression, end: Int) -> SourceExpression { value.located(start, end) }
        if take("(") { let value = try expression(); try expect(")"); return (located(value.value, end: tokens[max(0,cursor-1)].endByte),value.depth) }
        if text == "-" || (text == "+" && language.isJavaScriptFamily) || (text == "!" && language != .python) || (text == "not" && language == .python) {
            let op = text; cursor += 1
            let immediateLiteral = text.utf8.first.map { (48...57).contains($0) } == true
            let value = try expression(op == "not" ? 2 : 6)
            if op == "-", (language != .java || immediateLiteral), case .literal(let literal) = value.value.kind, !(language.isJavaScriptFamily && literal.hasPrefix("-")) { return (located(.literal("-" + literal), end: tokens[max(0,cursor-1)].endByte), 1) }
            let depth = try checkedDepth(value.depth + 1)
            return (located(.unary(op, value.value), end: tokens[max(0,cursor-1)].endByte), depth)
        }
        let value = text
        if let first = value.utf8.first, (48...57).contains(first) || (language.isJavaScriptFamily && first == 46) { cursor += 1; return (located(.literal(value), end: tokens[max(0,cursor-1)].endByte), 1) }
        let bools = language == .python ? ["True", "False"] : ["true", "false"]
        if bools.contains(value) { cursor += 1; return (located(.literal(value), end: tokens[max(0,cursor-1)].endByte), 1) }
        var name = try identifier()
        if language.isJavaScriptFamily && take(".") {
            name += "." + (try identifier())
            guard SourceNumberBuiltin.operation(name) != nil, text == "(" else { throw error("Unsupported member access") }
        }
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
            return (located(.call(name, arguments), end: tokens[max(0,cursor-1)].endByte), depth)
        }
        return (located(.variable(name), end: tokens[max(0,cursor-1)].endByte), 1)
    }
}
