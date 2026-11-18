import Foundation

public struct FormalTraceQuery: Codable, Sendable, Equatable {
    public let traceID: String
    public let start: Int
    public let count: Int
    public init(traceID: String, start: Int, count: Int) { self.traceID = traceID; self.start = start; self.count = count }
}
