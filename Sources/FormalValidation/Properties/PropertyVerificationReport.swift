import Foundation

public struct PropertyVerificationReport: Codable, Sendable {
    public struct Property: Codable, Sendable {
        public let specification: PropertySpecification.Property
        public let status: String
        public let lean: String
        public let tla: String
        public let executionBound: Int?
        public let logicalCaseSplits: Int?
        public let leanAxioms: [String]
        public let counterexample: [String]?
        public let counterexampleTLC: String?
        public let preconditionSatisfiability: String
        public let detail: String
        public let toolSeconds: [String: Double]
    }
    public let schemaVersion: Int
    public let scope: String
    public let translation: String
    public let artifactDataMatchesIR: Bool
    public let artifactSHA256: [String: String]
    public let specificationSHA256: String
    public let toolchain: ToolchainPolicy
    public let timeoutSeconds: Double
    public let properties: [Property]
    public let exitCode: Int32
    public let runDirectory: String
}
