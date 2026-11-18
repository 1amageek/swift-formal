import Foundation

public struct ArtifactReference: Codable, Sendable, Equatable {
    public let id: String
    public let sha256: String
    public let byteCount: Int
    public let mediaType: String
    public let profile: String
    public init(id: String, sha256: String, byteCount: Int, mediaType: String, profile: String) { self.id = id; self.sha256 = sha256; self.byteCount = byteCount; self.mediaType = mediaType; self.profile = profile }
}
