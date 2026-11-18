import FormalEvidence

public struct CompilationArtifactReference: Codable, Sendable, Equatable {
    public let sha256: String
    public let evidence: EvidenceBundleReference
    public init(sha256: String, evidence: EvidenceBundleReference) { self.sha256 = sha256; self.evidence = evidence }
}
