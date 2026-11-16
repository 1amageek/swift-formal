import Foundation
import FormalCore

struct LeanProofAudit {
    static func check(_ output: String, allowed: [String]) throws -> [String] {
        guard !output.lowercased().contains("sorry") else { throw invalid() }
        let lines = output.split(separator: "\n").filter { $0.hasPrefix("'checkedCase' ") }
        guard lines.count == 1, let line = lines.first else { throw invalid() }
        if line == "'checkedCase' does not depend on any axioms" { return [] }
        guard line.hasPrefix("'checkedCase' depends on axioms: ["), line.hasSuffix("]"),
              let open = line.firstIndex(of: "[") else { throw invalid() }
        let names = line[line.index(after: open)..<line.index(before: line.endIndex)].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard !names.isEmpty, Set(names).count == names.count, Set(names).isSubset(of: Set(allowed)) else { throw invalid() }
        return names.sorted()
    }
    private static func invalid() -> FormalDiagnostic { FormalDiagnostic(.toolFailure, "Missing or unauthorized Lean theorem dependencies") }
}
