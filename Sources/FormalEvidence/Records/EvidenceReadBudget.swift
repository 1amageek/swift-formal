import Foundation

public struct EvidenceReadBudget: Codable, Sendable, Equatable {
    public let maximumDatabaseBytes: Int
    public let maximumRecordBytes: Int
    public let maximumPageBytes: Int
    public let maximumNodes: Int
    public let maximumEdges: Int
    public let maximumTraversalNodes: Int
    public let maximumCursors: Int
    public init(maximumDatabaseBytes: Int, maximumRecordBytes: Int, maximumPageBytes: Int, maximumNodes: Int, maximumEdges: Int, maximumTraversalNodes: Int, maximumCursors: Int) { self.maximumDatabaseBytes = maximumDatabaseBytes; self.maximumRecordBytes = maximumRecordBytes; self.maximumPageBytes = maximumPageBytes; self.maximumNodes = maximumNodes; self.maximumEdges = maximumEdges; self.maximumTraversalNodes = maximumTraversalNodes; self.maximumCursors = maximumCursors }
}
