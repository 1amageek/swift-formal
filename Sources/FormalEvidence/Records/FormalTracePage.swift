import Foundation

public struct FormalTracePage: Codable, Sendable, Equatable {
    public let traceID: String
    public let graphID: String
    public let start: Int
    public let states: [String]
    public let transitions: [String]
    public let loopBackIndex: Int?
    public let totalSteps: Int
    public let complete: Bool
    public init(traceID: String, graphID: String, start: Int, states: [String], transitions: [String], loopBackIndex: Int? = nil, totalSteps: Int, complete: Bool) { self.traceID = traceID; self.graphID = graphID; self.start = start; self.states = states; self.transitions = transitions; self.loopBackIndex = loopBackIndex; self.totalSteps = totalSteps; self.complete = complete }
}
