import FormalCore

public struct SILLexer: Sendable {
    public let maximumTokens: Int

    public init(maximumTokens: Int = 2_000_000) { self.maximumTokens = maximumTokens }

    public func lex(_ source: String, path: String) throws -> [SILToken] {
        guard maximumTokens > 0 else {
            throw FormalDiagnostic(.invalidArguments, "Token limit must be positive.")
        }
        // A single UTF-8 scan buffer avoids repeated String index traversal. Token strings own
        // their text because syntax objects outlive the call and do not retain unsafe views.
        let bytes = Array(source.utf8)
        var tokens: [SILToken] = []
        var index = 0
        var line = 1
        var column = 1
        let punctuation: Set<UInt8> = [40, 41, 91, 93, 123, 125, 44, 58, 61, 60, 62]

        func failure(_ reason: String) -> FormalDiagnostic {
            FormalDiagnostic(.silParseFailed, "\(reason) at \(line):\(column)", path: path)
        }
        while index < bytes.count {
            guard tokens.count < maximumTokens else { throw failure("Token limit exceeded") }
            let byte = bytes[index]
            if byte == 32 || byte == 9 || byte == 13 {
                index += 1
                column += 1
                continue
            }
            if byte == 10 {
                tokens.append(SILToken(kind: .newline, text: "\n", line: line, column: column, startByte: index, endByte: index + 1))
                index += 1
                line += 1
                column = 1
                continue
            }
            if byte == 47, index + 1 < bytes.count, bytes[index + 1] == 47 {
                while index < bytes.count && bytes[index] != 10 { index += 1; column += 1 }
                continue
            }
            let start = index
            let startColumn = column
            let kind: SILToken.Kind
            if byte == 34 {
                kind = .string
                index += 1
                column += 1
                var closed = false
                while index < bytes.count {
                    guard bytes[index] != 10 else { throw failure("Unterminated string") }
                    if bytes[index] == 92 {
                        guard index + 1 < bytes.count else { throw failure("Unterminated string escape") }
                        index += 2
                        column += 2
                    } else if bytes[index] == 34 {
                        index += 1
                        column += 1
                        closed = true
                        break
                    } else { index += 1; column += 1 }
                }
                guard closed else { throw failure("Unterminated string") }
            } else if byte == 45, index + 1 < bytes.count, bytes[index + 1] == 62 {
                kind = .punctuation
                index += 2
                column += 2
            } else if punctuation.contains(byte) {
                kind = .punctuation
                index += 1
                column += 1
            } else {
                kind = .word
                while index < bytes.count {
                    let current = bytes[index]
                    if current <= 32 || current == 34 || punctuation.contains(current) { break }
                    if current == 47, index + 1 < bytes.count, bytes[index + 1] == 47 { break }
                    if current == 45, index + 1 < bytes.count, bytes[index + 1] == 62 { break }
                    guard current != 0 else { throw failure("NUL is not permitted") }
                    index += 1
                    column += 1
                }
            }
            guard index > start else { throw failure("Invalid token") }
            tokens.append(SILToken(kind: kind, text: String(decoding: bytes[start..<index], as: UTF8.self),
                                   line: line, column: startColumn, startByte: start, endByte: index))
        }
        return tokens
    }
}
