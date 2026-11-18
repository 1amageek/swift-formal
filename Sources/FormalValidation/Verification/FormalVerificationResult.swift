import FormalEvidence

public struct FormalVerificationResult: Codable, Sendable {
    public let schemaVersion: Int
    public let compilation: ArtifactReference
    public let compilationEvidence: EvidenceBundleReference
    public let specification: ArtifactReference
    public let evidence: EvidenceBundleReference
    public let claims: [VerificationClaim]
    public let graphs: [FormalGraphDescriptor]
    public let diagnostics: [String]
    public let exitCode: Int32
}
