import Foundation

public struct DocumentChunk: Codable, Sendable, Equatable {
    public let document: DocumentReference
    public let start: Int
    public let bytes: Data
    public let eof: Bool
    public init(document: DocumentReference, start: Int, bytes: Data, eof: Bool) { self.document = document; self.start = start; self.bytes = bytes; self.eof = eof }
}
