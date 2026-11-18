import Foundation

public struct VerificationClaim: Codable, Sendable, Equatable {
    public let id: String
    public let obligation: String
    public let proposition: String
    public let assumptions: [String]
    public let domain: String
    public let scope: String
    public let execution: String
    public let outcome: String
    public let translation: String
    public let toolIdentities: [String: String]
    public let artifactDigests: [String]
    public init(id: String, obligation: String, proposition: String, assumptions: [String], domain: String, scope: String, execution: String, outcome: String, translation: String, toolIdentities: [String: String], artifactDigests: [String]) { self.id = id; self.obligation = obligation; self.proposition = proposition; self.assumptions = assumptions; self.domain = domain; self.scope = scope; self.execution = execution; self.outcome = outcome; self.translation = translation; self.toolIdentities = toolIdentities; self.artifactDigests = artifactDigests }
}
