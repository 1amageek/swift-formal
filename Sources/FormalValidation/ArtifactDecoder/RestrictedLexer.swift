import FormalCore

struct RestrictedLexer {
    static func tokenize(_ source: String) throws -> [String] {
        guard source.utf8.count <= 16_777_216 else { throw mismatch("Artifact exceeds byte limit") }
        let bytes = Array(source.utf8)
        var tokens: [String] = []
        var offset = 0
        let delimiters: Set<UInt8> = [40, 41, 91, 93, 123, 125, 44, 58, 124, 60, 62, 61]
        while offset < bytes.count {
            let byte = bytes[offset]
            if [9, 10, 13, 32].contains(byte) { offset += 1; continue }
            let start = offset
            if byte == 34 {
                offset += 1
                var closed = false
                while offset < bytes.count {
                    if bytes[offset] == 92 { offset += 2 }
                    else if bytes[offset] == 34 { offset += 1; closed = true; break }
                    else {
                        guard bytes[offset] >= 32 else { throw mismatch("Control character in artifact string") }
                        offset += 1
                    }
                }
                guard closed, offset <= bytes.count else { throw mismatch("Unterminated artifact string") }
            } else if offset + 2 < bytes.count, byte == 124, bytes[offset + 1] == 45, bytes[offset + 2] == 62 { offset += 3 }
            else if offset + 1 < bytes.count,
                    (byte == 58 && bytes[offset + 1] == 61)
                    || (byte == 60 && bytes[offset + 1] == 60)
                    || (byte == 62 && bytes[offset + 1] == 62)
                    || (byte == 61 && bytes[offset + 1] == 61) { offset += 2 }
            else if delimiters.contains(byte) { offset += 1 }
            else {
                while offset < bytes.count, ![9, 10, 13, 32, 34].contains(bytes[offset]), !delimiters.contains(bytes[offset]) { offset += 1 }
            }
            guard offset > start else { throw mismatch("Invalid artifact token") }
            tokens.append(String(decoding: bytes[start..<offset], as: UTF8.self))
            guard tokens.count <= 2_000_000 else { throw mismatch("Artifact token limit exceeded") }
        }
        return tokens
    }

    static func mismatch(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.integrityMismatch, message) }
}
