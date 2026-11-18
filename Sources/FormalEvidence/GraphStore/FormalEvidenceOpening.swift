public protocol FormalEvidenceOpening: Sendable {
    func open(_ reference: EvidenceBundleReference, budget: EvidenceReadBudget) async throws -> any FormalEvidenceReading
}
