import Foundation

public struct EvidenceBundleReference: Codable, Sendable, Equatable {
    public let id: String
    public let sha256: String
    public let byteCount: Int
    public init(id: String, sha256: String, byteCount: Int) { self.id = id; self.sha256 = sha256; self.byteCount = byteCount }
}
