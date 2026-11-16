import FormalCore
import Foundation

struct RestrictedDataParser {
    let tokens: [String]
    let lean: Bool
    var cursor: Int

    mutating func value(depth: Int = 0) throws -> ArtifactData {
        guard depth < 128 else { throw bad("Artifact nesting limit exceeded") }
        let token = try next()
        if token.hasPrefix("\"") {
            guard let data = token.data(using: .utf8) else { throw bad("Invalid string encoding") }
            do {
                let text = try JSONDecoder().decode(String.self, from: data)
                return .text(text)
            }
            catch { throw bad("Invalid string escape") }
        }
        if let number = UInt64(token) { return .number(number) }
        if token == (lean ? "[" : "<<") {
            let end = lean ? "]" : ">>"
            var values: [ArtifactData] = []
            if consume(end) { return .list(values) }
            repeat {
                let element = try value(depth: depth + 1)
                values.append(element)
            } while consume(",")
            try expect(end)
            return .list(values)
        }
        if token == (lean ? "{" : "[") {
            let end = lean ? "}" : "]"
            var fields: [String: ArtifactData] = [:]
            if consume(end) { return .record(fields) }
            repeat {
                let key = try next()
                guard key.first?.isLetter == true, fields[key] == nil else { throw bad("Duplicate or invalid record field") }
                try expect(lean ? ":=" : "|->")
                fields[key] = try value(depth: depth + 1)
            } while consume(",")
            try expect(end)
            return .record(fields)
        }
        if lean && token == "(" {
            let name = try next()
            guard name.hasPrefix(".") else { throw bad("Unexpected Lean constructor") }
            var arguments: [ArtifactData] = []
            while !consume(")") {
                let argument = try value(depth: depth + 1)
                arguments.append(argument)
            }
            return .constructor(String(name.dropFirst()), arguments)
        }
        if lean && token.hasPrefix(".") { return .constructor(String(token.dropFirst()), []) }
        throw bad("Unexpected data token: \(token)")
    }

    mutating func next() throws -> String {
        guard cursor < tokens.count else { throw bad("Unexpected artifact end") }
        defer { cursor += 1 }
        return tokens[cursor]
    }

    mutating func consume(_ token: String) -> Bool {
        guard cursor < tokens.count, tokens[cursor] == token else { return false }
        cursor += 1
        return true
    }

    mutating func expect(_ token: String) throws {
        guard consume(token) else { throw bad("Expected artifact token: \(token)") }
    }

    private func bad(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.integrityMismatch, message) }
}
