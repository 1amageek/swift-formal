import Foundation

struct FiniteRunRecord: Codable, Sendable {
    struct Case: Codable, Sendable {
        let name: String
        let entry: String
        let irOutcome: String
        let irMatchesExpected: Bool
        let tlc: String
        let lean: String
        let leanAxioms: [String]
        let distinctStates: Int?
        let detail: String
    }
    let schemaVersion: Int
    let scope: String
    let translation: String
    let artifactDataMatchesIR: Bool
    let artifactSHA256: [String: String]
    let scenarioSHA256: String
    let toolchain: ToolchainPolicy
    let timeoutSeconds: Double
    let fuel: Int
    let cases: [Case]
    let exitCode: Int32
    let runDirectory: String
}
