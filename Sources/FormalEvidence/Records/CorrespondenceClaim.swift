import Foundation

public struct CorrespondenceClaim: Codable, Sendable, Equatable {
    public let sourceDigest: String
    public let modelDigest: String
    public let relation: String
    public let profile: String
    public let scope: String
    public let assumptions: [String]
    public let evidenceIDs: [String]
    public init(sourceDigest: String, modelDigest: String, relation: String, profile: String, scope: String, assumptions: [String], evidenceIDs: [String]) { self.sourceDigest = sourceDigest; self.modelDigest = modelDigest; self.relation = relation; self.profile = profile; self.scope = scope; self.assumptions = assumptions; self.evidenceIDs = evidenceIDs }
}
