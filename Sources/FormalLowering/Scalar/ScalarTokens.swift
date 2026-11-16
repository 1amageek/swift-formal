import FormalCore
import FormalIR

struct ScalarTokens {
    let tokens: [String]
    let path: String
    var index = 0

    init(_ tokens: [String], path: String) { self.tokens = tokens; self.path = path }

    var peek: String? { index < tokens.count ? tokens[index] : nil }

    mutating func next() throws -> String {
        guard index < tokens.count else { throw bad("Unexpected end of instruction") }
        let text = tokens[index]
        index += 1
        return text
    }

    mutating func consume(_ text: String) -> Bool {
        guard peek == text else { return false }
        index += 1
        return true
    }

    mutating func expect(_ text: String) throws {
        guard consume(text) else { throw bad("Expected \(text), found \(peek ?? "end")") }
    }

    func end() throws {
        guard index == tokens.count else {
            let text = tokens[index]
            let code: FormalDiagnostic.Code = text == "[" || text.hasPrefix("@") ? .unsupportedAttribute : .silParseFailed
            throw FormalDiagnostic(code, "Unexpected token: \(text)", path: path)
        }
    }

    mutating func value() throws -> String {
        let text = try next()
        guard text.hasPrefix("%"), text.count > 1,
              text.dropFirst().allSatisfy({ $0.isASCII && $0.isNumber }) else { throw bad("Expected a numeric SSA value") }
        return text
    }

    mutating func values() throws -> [String] {
        try expect("(")
        var result: [String] = []
        if consume(")") { return result }
        repeat {
            let id = try value()
            result.append(id)
        } while consume(",")
        try expect(")")
        return result
    }

    mutating func type(depth: Int = 0) throws -> IRType {
        guard depth < 128 else { throw bad("Type nesting limit exceeded") }
        _ = consume("$")
        if consume("(") {
            var fields: [IRType] = []
            if consume(")") { return .aggregate(fields) }
            repeat {
                let field = try type(depth: depth + 1)
                fields.append(field)
            } while consume(",")
            try expect(")")
            return .aggregate(fields)
        }
        var text = try next()
        if text.hasPrefix("$") { text.removeFirst() }
        if text.hasPrefix("Builtin.Int"), let width = Int(text.dropFirst("Builtin.Int".count)), (1...64).contains(width) {
            return .bits(width: width)
        }
        let wrappers = ["Bool": 1, "Int8": 8, "UInt8": 8, "Int16": 16, "UInt16": 16,
                        "Int32": 32, "UInt32": 32, "Int64": 64, "UInt64": 64]
        if let width = wrappers[text] { return .aggregate([.bits(width: width)]) }
        throw FormalDiagnostic(.unsupportedType, "Unsupported type: \(text)", path: path)
    }

    mutating func functionType() throws -> IRType {
        try expect("$@convention")
        try expect("(")
        try expect("thin")
        try expect(")")
        try expect("(")
        var parameters: [IRType] = []
        if !consume(")") {
            repeat {
                let parameter = try type()
                parameters.append(parameter)
            } while consume(",")
            try expect(")")
        }
        try expect("->")
        let result = try type()
        return .function(parameters: parameters, result: result)
    }

    private func bad(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.silParseFailed, message, path: path) }
}
