import Foundation

public struct OriginQuery: Codable, Sendable, Equatable {
    public let documentID: String
    public let start: Int
    public let count: Int
    public init(documentID: String, start: Int, count: Int) { self.documentID = documentID; self.start = start; self.count = count }
}
