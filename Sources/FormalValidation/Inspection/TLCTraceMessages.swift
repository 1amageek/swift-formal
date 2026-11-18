import Foundation
import FormalEvidence

struct TLCTraceMessages {
    struct Step { let index: Int; let action: String; let text: String }
    let steps: [Step]
    let loopBackIndex: Int?
    static func parse(_ output: String) throws -> Self {
        var steps: [Step] = [], current: Int?, body: [String] = [], loop: Int?
        func index(_ text: String) -> Int? { Int(text.prefix { $0.isNumber }) }
        for lineView in output.split(separator: "\n",omittingEmptySubsequences: false) {
            let line = String(lineView)
            if line.hasPrefix("@!@!@STARTMSG ") {
                guard current == nil else { throw FormalEvidenceError.integrity("Nested TLC tool message") }
                let suffix = line.dropFirst("@!@!@STARTMSG ".count)
                guard let code = index(String(suffix)), suffix.contains(":") else { throw FormalEvidenceError.integrity("Invalid TLC message header") }
                current = code; body = []
            } else if line.hasPrefix("@!@!@ENDMSG ") {
                let suffix = String(line.dropFirst("@!@!@ENDMSG ".count))
                guard let closing = index(suffix), closing == current else { throw FormalEvidenceError.integrity("Mismatched TLC message frame") }
                if current == 2217 {
                    guard let heading = body.first, let ordinal = index(heading), ordinal == steps.count + 1 else { throw FormalEvidenceError.integrity("Unordered TLC trace") }
                    let value = body.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty else { throw FormalEvidenceError.integrity("Missing trace state") }
                    steps.append(Step(index: ordinal - 1,action: heading,text: value))
                } else if current == 2122 || current == 2218 {
                    let text = body.joined(separator: " ")
                    if text.lowercased().contains("stuttering"), !steps.isEmpty { loop = steps.count - 1 }
                    else {
                        let expression = try NSRegularExpression(pattern: #"(?i)(?:back to state\s*|^)([0-9]+)"#)
                        if let match = expression.firstMatch(in: text,range: NSRange(text.startIndex...,in: text)), let range = Range(match.range(at: 1),in: text), let number = Int(text[range]), number > 0 { loop = number - 1 }
                        else { throw FormalEvidenceError.unsupported("Pinned TLC loop message shape") }
                    }
                }
                current = nil; body = []
            } else if current != nil { body.append(line) }
        }
        guard current == nil, loop.map({ $0 < steps.count }) ?? true else { throw FormalEvidenceError.integrity("Incomplete TLC trace message") }
        return Self(steps: steps,loopBackIndex: loop)
    }
}
