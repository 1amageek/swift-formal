import Foundation

public struct FormalGraphQuery: Codable, Sendable, Equatable {
    public let graphID: String
    public let roots: [String]
    public let relations: [String]
    public let direction: String
    public let depth: Int
    public let cursor: String?
    public init(graphID: String, roots: [String], relations: [String], direction: String, depth: Int, cursor: String? = nil) { self.graphID = graphID; self.roots = roots; self.relations = relations; self.direction = direction; self.depth = depth; self.cursor = cursor }
}
