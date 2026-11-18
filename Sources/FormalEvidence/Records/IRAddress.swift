import Foundation

public struct IRAddress: Codable, Sendable, Equatable, Hashable {
    public let programDigest: String
    public let function: String
    public let block: String?
    public let instruction: Int?
    public init(programDigest: String, function: String, block: String? = nil, instruction: Int? = nil) { self.programDigest = programDigest; self.function = function; self.block = block; self.instruction = instruction }
}
