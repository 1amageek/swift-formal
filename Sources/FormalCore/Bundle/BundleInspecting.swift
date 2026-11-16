import Foundation

public protocol BundleInspecting: Sendable {
    func inspect(at root: URL, expectedLock: ToolchainLock) throws -> BundleInspection
}
