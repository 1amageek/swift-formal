import Foundation

public struct FormalNode: Codable, Sendable, Equatable {
    public let id: String
    public let kind: String
    public let label: String
    public let attributes: [String: String]
    public let ranges: [TextRange]
    public let claimIDs: [String]
    public let stateValue: StateValue?
    public init(id: String, kind: String, label: String, attributes: [String: String], ranges: [TextRange], claimIDs: [String], stateValue: StateValue? = nil) { self.id = id; self.kind = kind; self.label = label; self.attributes = attributes; self.ranges = ranges; self.claimIDs = claimIDs; self.stateValue = stateValue }
}
