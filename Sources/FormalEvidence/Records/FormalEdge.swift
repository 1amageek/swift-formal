import Foundation

public struct FormalEdge: Codable, Sendable, Equatable {
    public let id: String
    public let source: String
    public let target: String
    public let kind: String
    public let attributes: [String: String]
    public init(id: String, source: String, target: String, kind: String, attributes: [String: String]) { self.id = id; self.source = source; self.target = target; self.kind = kind; self.attributes = attributes }
}
