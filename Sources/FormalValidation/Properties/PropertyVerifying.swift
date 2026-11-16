import Foundation

public protocol PropertyVerifying: Sendable {
    func check(artifact: URL, properties: URL, toolchain: BundledToolchain, timeout: Double) async throws -> PropertyVerificationReport
}
