import Foundation

public struct OriginPage: Codable, Sendable, Equatable {
    public let origins: [OriginLink]
    public let nextOffset: Int?
    public init(origins: [OriginLink], nextOffset: Int? = nil) { self.origins = origins; self.nextOffset = nextOffset }
}
