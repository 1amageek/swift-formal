import Foundation
import CryptoKit
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

    public static func policyResourceURL() throws -> URL {
        guard let url = Bundle.module.url(forResource: "toolchain-artifacts.lock", withExtension: "json") else {
            throw FormalDiagnostic(.ioFailure, "Missing pinned toolchain policy")
        }
        return url
    }
    public static func bundled() throws -> Self {
        let url = try policyResourceURL()
        return try ArtifactJSON.read(Self.self, from: url)
    }
    public static func resourceIdentity() throws -> String {
        var values: [String: String] = [:]
        for name in ["toolchain-artifacts.lock", "trusted-artifacts"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "json") else { throw FormalDiagnostic(.ioFailure, "Missing validation resource") }
            let bytes = try ArtifactJSON.readBytes(from: url, maximumBytes: 1_000_000)
            values[name] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(values)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    public static var resourceBundle: URL { Bundle.module.bundleURL }
}
