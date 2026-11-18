import Foundation
import FormalEvidence

struct VerificationClaimFactory {
    static func artifact(_ bytes: Data,profile: String) -> ArtifactReference {
        let hash = EvidenceIdentity.digest(bytes)
        return ArtifactReference(id: hash,sha256: hash,byteCount: bytes.count,mediaType: "application/json",profile: profile)
    }
    static func context(snapshot: ArtifactSnapshot,specification: ArtifactReference,tools: BundledToolchain) throws -> String {
        let resources = try CollectorResources.identity()
        return EvidenceIdentity.id("verification-context",snapshot.compilation.sha256,specification.sha256,tools.policy.inventorySHA256,resources)
    }
    static func claim(context: String,obligation: String,proposition: String,domain: String,scope: String,status: String,axioms: [String],tools: BundledToolchain,artifacts: [String]) -> VerificationClaim {
        let outcome: String
        switch status {
        case "PROVED": outcome = "proved"
        case "MODEL_CHECKED": outcome = "modelChecked"
        case "COUNTEREXAMPLE", "COUNTEREXAMPLE_PROVED": outcome = "counterexample"
        case "UNPROVED": outcome = "unproved"
        default: outcome = "unknown"
        }
        return VerificationClaim(id: EvidenceIdentity.id("verification-claim",context,obligation,domain),obligation: obligation,proposition: proposition,assumptions: axioms,domain: domain,scope: scope,execution: outcome == "unknown" ? "incomplete" : "completed",outcome: outcome,translation: "UNVALIDATED",toolIdentities: ["toolchain":tools.policy.inventorySHA256],artifactDigests: artifacts)
    }
}
