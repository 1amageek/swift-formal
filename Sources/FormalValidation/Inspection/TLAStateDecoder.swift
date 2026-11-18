import Foundation
import FormalEvidence

// The UTF-8 view retains the input's immutable backing; no byte array is copied.
// Unsupported TLC values remain exact opaque text, never fabricated empty values.
struct TLAStateDecoder {
    private let bytes: String.UTF8View
    private var position: String.UTF8View.Index
    private let maximumDepth: Int
    init(_ text: String,maximumDepth: Int) { bytes = text.utf8; position = bytes.startIndex; self.maximumDepth = maximumDepth }
    mutating func decode() -> StateValue {
        let original = position
        do {
            var bindings: [String: StateValue] = [:]
            skip()
            while position < bytes.endIndex {
                _ = take("/\\"); skip()
                let key = try name(); skip(); try require("=")
                guard bindings[key] == nil else { throw FormalEvidenceError.integrity("Duplicate state variable") }
                bindings[key] = try value(0); skip()
            }
            guard !bindings.isEmpty else { throw FormalEvidenceError.integrity("Empty state") }
            return .record(bindings)
        } catch { return .opaque(String(decoding: bytes[original...],as: UTF8.self)) }
    }
    static func status(_ value: StateValue) -> String? {
        guard case .record(let variables) = value, case .record(let state) = variables["state"], case .string(let status) = state["status"] else { return nil }
        return status
    }
    private mutating func value(_ depth: Int) throws -> StateValue {
        guard depth < maximumDepth else { throw FormalEvidenceError.limit("State value nesting") }
        skip()
        if peek() == 34 { return .string(try quoted()) }
        if take("TRUE") { return .boolean(true) }; if take("FALSE") { return .boolean(false) }
        if take("<<") {
            var values: [StateValue] = []; skip()
            if take(">>") { return .sequence(values) }
            repeat { values.append(try value(depth + 1)); skip() } while take(",")
            try require(">>"); return .sequence(values)
        }
        if take("{") {
            var values: [StateValue] = []; skip()
            if take("}") { return .set(values) }
            repeat { values.append(try value(depth + 1)); skip() } while take(",")
            try require("}"); return .set(values)
        }
        if take("[") {
            var fields: [String: StateValue] = [:]; skip()
            if take("]") { return .record(fields) }
            repeat {
                skip(); let key = peek() == 34 ? try quoted() : try name()
                skip(); try require("|->")
                guard fields[key] == nil else { throw FormalEvidenceError.integrity("Duplicate record field") }
                fields[key] = try value(depth + 1); skip()
            } while take(",")
            try require("]"); return .record(fields)
        }
        if let byte = peek(), byte == 45 || (48...57).contains(byte) {
            let start = position; if byte == 45 { advance() }
            let digits = position
            while let byte = peek(), (48...57).contains(byte) { advance() }
            guard position != digits else { throw FormalEvidenceError.integrity("Invalid integer") }
            return .integer(String(decoding: bytes[start..<position],as: UTF8.self))
        }
        return .opaque(try opaque())
    }
    private mutating func name() throws -> String {
        let start = position
        while let byte = peek(), (65...90).contains(byte) || (97...122).contains(byte) || (48...57).contains(byte) || byte == 95 { advance() }
        guard position != start else { throw FormalEvidenceError.integrity("Missing state field") }
        return String(decoding: bytes[start..<position],as: UTF8.self)
    }
    private mutating func quoted() throws -> String {
        try require("\""); var output = Data()
        while let byte = peek() {
            advance()
            if byte == 34 { guard let text = String(data: output,encoding: .utf8) else { throw FormalEvidenceError.integrity("Invalid state string") }; return text }
            if byte == 92 {
                guard let escaped = peek() else { throw FormalEvidenceError.integrity("Truncated state string") }; advance()
                switch escaped { case 110: output.append(10); case 114: output.append(13); case 116: output.append(9); case 34,92: output.append(escaped); default: throw FormalEvidenceError.unsupported("Pinned TLC string escape") }
            } else { output.append(byte) }
        }
        throw FormalEvidenceError.integrity("Unterminated state string")
    }
    private mutating func opaque() throws -> String {
        let start = position; var stack: [UInt8] = []
        while let byte = peek() {
            if stack.isEmpty && (byte == 44 || byte == 93 || byte == 125 || starts(">>") || starts("/\\")) { break }
            if byte == 34 { _ = try quoted(); continue }
            if byte == 40 || byte == 91 || byte == 123 { stack.append(byte) }
            else if byte == 41 || byte == 93 || byte == 125 {
                guard !stack.isEmpty else { break }; stack.removeLast()
            }
            guard stack.count < maximumDepth else { throw FormalEvidenceError.limit("Opaque value nesting") }
            advance()
        }
        guard position != start, stack.isEmpty else { throw FormalEvidenceError.integrity("Invalid opaque value") }
        return String(decoding: bytes[start..<position],as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func peek() -> UInt8? { position < bytes.endIndex ? bytes[position] : nil }
    private mutating func advance() { bytes.formIndex(after: &position) }
    private mutating func skip() { while let byte = peek(), [9,10,13,32].contains(byte) { advance() } }
    private func starts(_ text: String) -> Bool { bytes[position...].starts(with: text.utf8) }
    private mutating func take(_ text: String) -> Bool {
        guard starts(text) else { return false }
        for _ in text.utf8 { advance() }; return true
    }
    private mutating func require(_ text: String) throws { skip(); guard take(text) else { throw FormalEvidenceError.integrity("Unexpected state token") } }
}
