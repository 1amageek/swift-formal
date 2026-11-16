import Foundation

public protocol ToolchainProviding: Sendable {
    func verify(at root: URL) throws -> BundledToolchain
    func prepare(at root: URL, cache: URL) async throws -> BundledToolchain
}
