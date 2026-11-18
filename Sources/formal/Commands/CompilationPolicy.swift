import FormalEvidence

struct CompilationPolicy {
    static let budget = EvidenceReadBudget(maximumDatabaseBytes: 536_870_912,maximumRecordBytes: 262_144,maximumPageBytes: 1_048_576,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 64)
}
