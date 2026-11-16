struct SourceLexer {
    static func tokenize(_ source: String, language: SourceLanguage, maximumBytes: Int, maximumTokens: Int) throws -> [SourceToken] {
        func fail(_ message: String, _ line: Int, _ column: Int) -> SourceDiagnostic {
            .init(language: language, line: line, column: column, message: message)
        }
        guard source.utf8.count <= maximumBytes, source.utf8.allSatisfy({ $0 < 128 && $0 != 0 }) else {
            throw fail("Source exceeds byte limit or contains non-ASCII data", 1, 1)
        }
        let bytes = Array(source.utf8)
        if language == .java, bytes.contains(92) {
            throw fail("Java Unicode escapes and backslashes are outside this profile", 1, 1)
        }
        if language == .java || language == .bun {
            for index in bytes.indices where bytes[index] == 13 {
                guard index + 1 < bytes.count, bytes[index + 1] == 10 else { throw fail("Use LF or CRLF line endings", 1, 1) }
            }
        }
        var i = 0; var line = 1; var column = 1; var tokens: [SourceToken] = []
        var atLineStart = true; var indents = [0]; var commentDepth = 0; var headers: Set<String> = []
        func isName(_ byte: UInt8) -> Bool { (65...90).contains(byte) || (97...122).contains(byte) || byte == 95 }
        func emit(_ text: String, _ l: Int, _ c: Int) throws {
            guard tokens.count < maximumTokens else { throw fail("Token limit exceeded", l, c) }
            tokens.append(.init(text: text, line: l, column: c))
        }
        func advance() {
            if bytes[i] == 10 { line += 1; column = 1; atLineStart = true }
            else { column += 1 }
            i += 1
        }
        while i < bytes.count {
            let b = bytes[i]
            if commentDepth > 0 {
                if i + 1 < bytes.count, b == 47, bytes[i+1] == 42 {
                    guard language == .rust || language == .swift else { throw fail("Nested block comments are outside this profile", line, column) }
                    commentDepth += 1; advance(); advance()
                } else if i + 1 < bytes.count, b == 42, bytes[i+1] == 47 { commentDepth -= 1; advance(); advance() }
                else { if b == 10 { try emit("\n", line, column) }; advance() }
                continue
            }
            if language == .python && atLineStart {
                var count = 0
                while i < bytes.count && bytes[i] == 32 { count += 1; advance() }
                guard i == bytes.count || bytes[i] != 9 else { throw fail("Python indentation requires spaces", line, column) }
                if i == bytes.count { break }
                if bytes[i] != 10 && bytes[i] != 13 && bytes[i] != 35 {
                    if count > indents.last! { indents.append(count); try emit("<indent>", line, 1) }
                    while count < indents.last! { indents.removeLast(); try emit("<dedent>", line, 1) }
                    guard count == indents.last! else { throw fail("Inconsistent indentation", line, column) }
                }
                atLineStart = false
                continue
            }
            if b == 10 { try emit("\n", line, column); advance(); continue }
            if [9, 13, 32].contains(b) { advance(); continue }
            atLineStart = false
            if b == 35 {
                let start = i; let l = line
                while i < bytes.count && bytes[i] != 10 { advance() }
                if language == .python { continue }
                let directive = String(decoding: bytes[start..<i], as: UTF8.self).filter { $0 != " " && $0 != "\t" }
                let allowed = language == .c ? ["#include<stdint.h>", "#include<stdbool.h>"] : language == .cpp ? ["#include<cstdint>", "#include<stdint.h>"] : []
                guard allowed.contains(directive), tokens.allSatisfy({ $0.text == "\n" }) else { throw fail("Unsupported preprocessor directive", l, 1) }
                headers.insert(directive)
                continue
            }
            if i+1 < bytes.count && b == 47 && bytes[i+1] == 47 && language != .python {
                while i < bytes.count && bytes[i] != 10 { advance() }; continue
            }
            if i+1 < bytes.count && b == 47 && bytes[i+1] == 42 && language != .python {
                guard language != .go else { throw fail("Block comments are outside the Go source profile", line, column) }
                commentDepth = 1; advance(); advance(); continue
            }
            let start = i; let l = line; let c = column
            if isName(b) || (48...57).contains(b) {
                advance()
                while i < bytes.count && (isName(bytes[i]) || (48...57).contains(bytes[i])) { advance() }
                try emit(String(decoding: bytes[start..<i], as: UTF8.self), l, c); continue
            }
            let pair = i+1 < bytes.count ? String(decoding: bytes[i...i+1], as: UTF8.self) : ""
            if ["++", "--"].contains(pair), [.c, .cpp, .javascript, .typescript, .go, .swift, .java, .bun].contains(language) {
                throw fail("Unsupported update operator '\(pair)'", l, c)
            }
            if ["->", "==", "!=", "<=", ">=", ":=", "::"].contains(pair) { advance(); advance(); try emit(pair, l, c); continue }
            guard "(){}:;,+-*<>=!".utf8.contains(b) else { throw fail("Unsupported character or operator", l, c) }
            advance(); try emit(String(decoding: [b], as: UTF8.self), l, c)
        }
        if language == .c || language == .cpp {
            if tokens.contains(where: { ["int64_t", "uint64_t"].contains($0.text) }) && !headers.contains(where: { $0.contains("stdint") }) {
                throw fail("The integer profile requires a standard integer header", 1, 1)
            }
            if language == .c && tokens.contains(where: { ["bool", "true", "false"].contains($0.text) }) && !headers.contains("#include<stdbool.h>") {
                throw fail("C11 Boolean values require stdbool.h", 1, 1)
            }
        }
        guard commentDepth == 0 else { throw fail("Unterminated block comment", line, column) }
        if tokens.last?.text != "\n" { try emit("\n", line, column) }
        while indents.count > 1 { indents.removeLast(); try emit("<dedent>", line, column) }
        try emit("<eof>", line, column)
        return tokens
    }
}
