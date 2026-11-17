import Foundation
import FormalCore

struct SANYOutputAudit {
    static func check(_ output: String, module: String) throws {
        let diagnostics = try NSRegularExpression(pattern: "(?im)^[\\t ]*(\\*{3}[^\\r\\n]*error|(?:semantic|fatal) errors?:|exception in thread\\b)")
        let range = NSRange(output.startIndex..., in: output)
        let hasDiagnostics = diagnostics.numberOfMatches(in: output, range: range) != 0
        let expected = "Semantic processing of module " + module
        let completed = output.split(whereSeparator: \.isNewline).contains {
            $0.trimmingCharacters(in: .whitespaces) == expected
        }
        guard completed, !hasDiagnostics else {
            throw FormalDiagnostic(.toolFailure, "SANY did not establish error-free semantic processing of module " + module)
        }
    }
}
