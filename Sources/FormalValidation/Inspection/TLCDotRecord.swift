import Foundation
import FormalEvidence

struct TLCDotRecord {
    let source: String
    let target: String?
    let label: String
    let initial: Bool
    static func parse(_ line: String) throws -> Self? {
        let text = line.trimmingCharacters(in: .whitespaces)
        guard let first = text.utf8.first, first == 45 || (48...57).contains(first) else { return nil }
        let expression = try NSRegularExpression(pattern: #"^(-?[0-9]+)(?:\s*->\s*(-?[0-9]+))?\s*\[label=\""#)
        guard let match = expression.firstMatch(in: text,range: NSRange(text.startIndex...,in: text)), let sourceRange = Range(match.range(at: 1),in: text), let end = Range(match.range,in: text)?.upperBound else { throw FormalEvidenceError.integrity("Invalid pinned TLC DOT record") }
        let source = String(text[sourceRange]), target = Range(match.range(at: 2),in: text).map { String(text[$0]) }
        var output = "", escaped = false, index = end
        while index < text.endIndex {
            let character = text[index]; text.formIndex(after: &index)
            if escaped {
                switch character { case "n","l": output.append("\n"); case "r": output.append("\r"); case "t": output.append("\t"); case "\"","\\": output.append(character); default: output.append("\\"); output.append(character) }; escaped = false
            } else if character == "\\" { escaped = true }
            else if character == "\"" {
                let attributes = text[index...]
                return Self(source: source,target: target,label: output,initial: target == nil && attributes.contains("style = filled"))
            } else { output.append(character) }
        }
        throw FormalEvidenceError.integrity("Unterminated TLC label")
    }
}
