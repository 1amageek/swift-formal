import Foundation

public protocol ModelVerifying: Sendable {
    func check(artifact: URL, scenario: URL, toolchain: BundledToolchain, timeout: Double) async throws -> VerificationReport
}
