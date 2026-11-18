struct EvidenceBudget {
    static func validate(_ budget: EvidenceReadBudget) throws {
        guard budget.maximumDatabaseBytes > 0, budget.maximumRecordBytes > 0,
            budget.maximumPageBytes >= budget.maximumRecordBytes, budget.maximumNodes >= 2,
            budget.maximumEdges > 0, budget.maximumTraversalNodes > 0, budget.maximumCursors > 0,
            budget.maximumTraversalNodes <= 1_000_000, budget.maximumPageBytes <= 64 * 1024 * 1024 else { throw FormalEvidenceError.invalid("Evidence budget") }
    }
}
