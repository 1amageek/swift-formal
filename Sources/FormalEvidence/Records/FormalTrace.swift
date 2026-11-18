import Foundation

public struct FormalTrace: Codable, Sendable, Equatable {
    public let id: String
    public let graphID: String
    public let states: [String]
    public let transitions: [String]
    public let loopBackIndex: Int?
    public let obligation: String
    public let complete: Bool
    public init(id: String, graphID: String, states: [String], transitions: [String], loopBackIndex: Int? = nil, obligation: String, complete: Bool) { self.id = id; self.graphID = graphID; self.states = states; self.transitions = transitions; self.loopBackIndex = loopBackIndex; self.obligation = obligation; self.complete = complete }
}
