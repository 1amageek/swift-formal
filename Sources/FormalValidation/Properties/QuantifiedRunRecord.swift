import Foundation

struct QuantifiedRunRecord: Codable, Sendable {
    struct Property: Codable, Sendable {
        let specification: PropertySpecification.Property
        let status: String
        let lean: String
        let tla: String
        let executionBound: Int?
        let logicalCaseSplits: Int?
        let leanAxioms: [String]
        let counterexample: [String]?
        let counterexampleTLC: String?
        let preconditionSatisfiability: String
        let detail: String
        let toolSeconds: [String: Double]
    }
    let schemaVersion: Int
    let scope: String
    let translation: String
    let artifactDataMatchesIR: Bool
    let artifactSHA256: [String: String]
    let specificationSHA256: String
    let toolchain: ToolchainPolicy
    let timeoutSeconds: Double
    let properties: [Property]
    let exitCode: Int32
    let runDirectory: String
}
