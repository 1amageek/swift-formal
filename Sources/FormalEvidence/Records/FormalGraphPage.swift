import Foundation

public struct FormalGraphPage: Codable, Sendable, Equatable {
    public let graphID: String
    public let nodes: [FormalNode]
    public let edges: [FormalEdge]
    public let frontier: [String]
    public let selectionComplete: Bool
    public let nextCursor: String?
    public init(graphID: String, nodes: [FormalNode], edges: [FormalEdge], frontier: [String], selectionComplete: Bool, nextCursor: String? = nil) { self.graphID = graphID; self.nodes = nodes; self.edges = edges; self.frontier = frontier; self.selectionComplete = selectionComplete; self.nextCursor = nextCursor }
}
