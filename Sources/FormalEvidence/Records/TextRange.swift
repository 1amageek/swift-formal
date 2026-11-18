import Foundation

public struct TextRange: Codable, Sendable, Equatable {
    public let documentID: String
    public let start: Int
    public let end: Int
    public init(documentID: String, start: Int, end: Int) { self.documentID = documentID; self.start = start; self.end = end }
}
