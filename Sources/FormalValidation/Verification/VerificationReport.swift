import Foundation

public struct VerificationReport: Codable, Sendable {
    public struct Case: Codable, Sendable {
        public let name: String
        public let entry: String
        public let irOutcome: String
        public let irMatchesExpected: Bool
        public let tlc: String
        public let lean: String
        public let leanAxioms: [String]
        public let distinctStates: Int?
        public let detail: String
    }
    public let schemaVersion: Int
    public let scope: String
    public let translation: String
    public let artifactDataMatchesIR: Bool
    public let artifactSHA256: [String: String]
    public let scenarioSHA256: String
    public let toolchain: ToolchainPolicy
    public let timeoutSeconds: Double
    public let fuel: Int
    public let cases: [Case]
    public let exitCode: Int32
    public let runDirectory: String
}
