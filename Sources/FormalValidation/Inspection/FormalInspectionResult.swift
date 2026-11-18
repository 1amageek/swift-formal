import FormalEvidence

public struct FormalInspectionResult: Codable, Sendable {
    public let schemaVersion: Int
    public let evidence: EvidenceBundleReference
    public let graphs: [FormalGraphDescriptor]
    public let claims: [VerificationClaim]
}
