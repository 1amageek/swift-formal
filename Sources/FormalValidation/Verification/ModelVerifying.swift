import Foundation
import FormalEvidence

public protocol ModelVerifying: Sendable {
    func check(artifact: URL, scenario: URL, output: URL, evidenceBudget: EvidenceReadBudget, toolchain: BundledToolchain, timeout: Double) async throws -> FormalVerificationResult
}
