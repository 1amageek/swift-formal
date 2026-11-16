import Foundation
import FormalCore

public struct ToolchainPolicy: Codable, Sendable {
    public struct Artifact: Codable, Sendable {
        public let version: String
        public let url: String
        public let sha256: String
    }
    public let schemaVersion: Int
    public let lean: Artifact
    public let tla: Artifact
    public let java: Artifact
    public let inventorySHA256: String
    public let allowedLeanAxioms: [String]

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "toolchain-artifacts.lock", withExtension: "json") else {
            throw FormalDiagnostic(.ioFailure, "Missing pinned toolchain policy")
        }
        return try ArtifactJSON.read(Self.self, from: url)
    }
    public static var resourceBundle: URL { Bundle.module.bundleURL }
}
