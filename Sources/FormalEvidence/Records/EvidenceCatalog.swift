import Foundation

public struct EvidenceCatalog: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let graphs: [FormalGraphDescriptor]
    public let documents: [DocumentReference]
    public let traces: [String]
    public let claims: [VerificationClaim]
    public init(schemaVersion: Int, graphs: [FormalGraphDescriptor], documents: [DocumentReference], traces: [String], claims: [VerificationClaim]) { self.schemaVersion = schemaVersion; self.graphs = graphs; self.documents = documents; self.traces = traces; self.claims = claims }
}
