import Foundation
import FormalEvidence

public protocol PropertyVerifying: Sendable {
    func check(artifact: URL, properties: URL, output: URL, evidenceBudget: EvidenceReadBudget, toolchain: BundledToolchain, timeout: Double) async throws -> FormalVerificationResult
}
