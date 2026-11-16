import FormalCore

public struct CanonicalSILParser: SILParsing {
    public let maximumTokens: Int
    public let maximumNesting: Int

    public init(maximumTokens: Int = 2_000_000, maximumNesting: Int = 256) {
        self.maximumTokens = maximumTokens
        self.maximumNesting = maximumNesting
    }

    public func parse(_ source: String, path: String) throws -> SILModuleSyntax {
        guard maximumNesting > 0 else {
            throw FormalDiagnostic(.invalidArguments, "Nesting limit must be positive.")
        }
        let tokens = try SILLexer(maximumTokens: maximumTokens).lex(source, path: path)
        var reader = Reader(tokens: tokens, path: path, maximumNesting: maximumNesting)
        return try reader.module()
    }
}

private struct Reader {
    let tokens: [SILToken]
    let path: String
    let maximumNesting: Int
    var cursor = 0

    mutating func module() throws -> SILModuleSyntax {
        skipNewlines()
        try expect("sil_stage")
        try expect("canonical")
        guard cursor == tokens.count || tokens[cursor].kind == .newline else { throw error("Invalid SIL stage declaration") }
        var functions: [SILModuleSyntax.Function] = []
        var declarations: [[SILToken]] = []
        var bodySymbols = Set<String>()
        while cursor < tokens.count {
            skipNewlines()
            guard cursor < tokens.count else { break }
            if tokens[cursor].text == "sil" {
                let function = try function()
                if function.hasBody && !bodySymbols.insert(function.symbol).inserted {
                    throw error("Duplicate function body: \(function.symbol)")
                }
                functions.append(function)
            } else {
                let declaration = try record(stopAtFunctionBrace: false)
                declarations.append(declaration)
            }
        }
        return SILModuleSyntax(path: path, functions: functions, declarations: declarations,
                               semanticValidationPerformed: false)
    }

    mutating func function() throws -> SILModuleSyntax.Function {
        let line = tokens[cursor].line
        let header = try record(stopAtFunctionBrace: true)
        guard let colon = header.firstIndex(where: { $0.text == ":" }), colon > 1,
              header[colon - 1].text.hasPrefix("@"), header[colon - 1].text.count > 1 else {
            throw error("Function requires a mangled symbol and type")
        }
        let symbol = String(header[colon - 1].text.dropFirst())
        guard header.dropFirst(colon + 1).contains(where: { $0.text == "->" }) else {
            throw error("Function type is missing its result arrow")
        }
        guard cursor < tokens.count && tokens[cursor].text == "{" else {
            return SILModuleSyntax.Function(symbol: symbol, header: header, blocks: [], hasBody: false, line: line)
        }
        cursor += 1
        var blocks: [SILModuleSyntax.Block] = []
        var blockIDs = Set<String>()
        var blockID: String?
        var blockArguments: [SILToken] = []
        var instructions: [SILModuleSyntax.Instruction] = []
        while cursor < tokens.count {
            skipNewlines()
            guard cursor < tokens.count else { throw error("Unterminated function") }
            if tokens[cursor].text == "}" {
                cursor += 1
                if let blockID {
                    guard !instructions.isEmpty else { throw error("Empty basic block") }
                    blocks.append(.init(id: blockID, arguments: blockArguments, instructions: instructions))
                }
                guard !blocks.isEmpty else { throw error("A function body requires basic blocks") }
                return SILModuleSyntax.Function(symbol: symbol, header: header, blocks: blocks, hasBody: true, line: line)
            }
            let record = try record(stopAtFunctionBrace: false)
            guard !record.isEmpty else { continue }
            if record[0].text.hasPrefix("bb"), record.last?.text == ":" {
                if let blockID {
                    guard !instructions.isEmpty else { throw error("Empty basic block") }
                    blocks.append(.init(id: blockID, arguments: blockArguments, instructions: instructions))
                }
                blockID = record[0].text
                guard blockIDs.insert(record[0].text).inserted else { throw error("Duplicate basic block") }
                blockArguments = Array(record.dropFirst().dropLast())
                instructions = []
            } else {
                guard blockID != nil else { throw error("Instruction outside a basic block") }
                let parsed = try instruction(record)
                instructions.append(parsed)
            }
        }
        throw error("Unterminated function")
    }

    func instruction(_ record: [SILToken]) throws -> SILModuleSyntax.Instruction {
        let equals = record.firstIndex(where: { $0.text == "=" })
        let opcodeIndex = equals.map { $0 + 1 } ?? 0
        guard opcodeIndex < record.count, record[opcodeIndex].kind == .word else {
            throw error("Instruction requires an opcode")
        }
        var results: [String] = []
        if let equals {
            let binding = record[..<equals]
            guard !binding.isEmpty, binding.allSatisfy({
                $0.text.hasPrefix("%") || ["(", ")", ","].contains($0.text)
            }) else { throw error("Malformed instruction result binding") }
            results = binding.filter { $0.text.hasPrefix("%") }.map(\.text)
            guard !results.isEmpty, Set(results).count == results.count else { throw error("Malformed result binding") }
        }
        return SILModuleSyntax.Instruction(results: results, opcode: record[opcodeIndex].text,
            operands: Array(record.dropFirst(opcodeIndex + 1)), line: record[0].line)
    }

    mutating func record(stopAtFunctionBrace: Bool) throws -> [SILToken] {
        var result: [SILToken] = []
        var stack: [String] = []
        let matches = [")": "(", "]": "[", "}": "{", ">": "<"]
        while cursor < tokens.count {
            let token = tokens[cursor]
            if token.kind == .newline, stack.isEmpty {
                cursor += 1
                // Comma-continued instruction operands may span physical lines.
                if result.last?.text == "," { continue }
                return result
            }
            if stopAtFunctionBrace && token.text == "{" && stack.isEmpty { return result }
            if token.text == "}" && stack.isEmpty { throw error("Unexpected closing brace") }
            if ["(", "[", "{"].contains(token.text) || (token.text == "<" && stopAtFunctionBrace) {
                stack.append(token.text)
                guard stack.count <= maximumNesting else { throw error("Nesting limit exceeded") }
            } else if let opening = matches[token.text], token.text != ">" || stack.last == "<" {
                guard stack.last == opening else { throw error("Mismatched delimiter") }
                stack.removeLast()
            }
            if token.kind != .newline { result.append(token) }
            cursor += 1
        }
        guard stack.isEmpty else { throw error("Unterminated delimiter") }
        guard !result.isEmpty else { throw error("Empty record") }
        return result
    }

    mutating func skipNewlines() {
        while cursor < tokens.count && tokens[cursor].kind == .newline { cursor += 1 }
    }

    mutating func expect(_ text: String) throws {
        guard cursor < tokens.count && tokens[cursor].text == text else { throw error("Expected \(text)") }
        cursor += 1
    }

    func error(_ message: String) -> FormalDiagnostic {
        let position = cursor < tokens.count ? "\(tokens[cursor].line):\(tokens[cursor].column)" : "end of input"
        return FormalDiagnostic(.silParseFailed, "\(message) at \(position)", path: path)
    }
}
