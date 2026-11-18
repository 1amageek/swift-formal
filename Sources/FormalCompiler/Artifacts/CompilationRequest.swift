import Foundation
import FormalEvidence

public struct CompilationRequest: Sendable {
    public let source: Data
    public let language: SourceLanguage
    public let moduleID: String
    public let evidenceBudget: EvidenceReadBudget
    public init(source: Data, language: SourceLanguage, moduleID: String, evidenceBudget: EvidenceReadBudget) {
        self.source = source; self.language = language; self.moduleID = moduleID; self.evidenceBudget = evidenceBudget
    }
}
