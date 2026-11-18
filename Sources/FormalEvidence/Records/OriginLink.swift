import Foundation

public struct OriginLink: Codable, Sendable, Equatable {
    public let id: String
    public let source: TextRange?
    public let address: IRAddress?
    public let generated: TextRange?
    public let precision: String
    public let producer: String
    public let synthetic: Bool
    public init(id: String, source: TextRange? = nil, address: IRAddress? = nil, generated: TextRange? = nil, precision: String, producer: String, synthetic: Bool) { self.id = id; self.source = source; self.address = address; self.generated = generated; self.precision = precision; self.producer = producer; self.synthetic = synthetic }
}
