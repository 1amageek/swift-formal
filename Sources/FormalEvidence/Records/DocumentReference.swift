import Foundation

public struct DocumentReference: Codable, Sendable, Equatable {
    public let id: String
    public let sha256: String
    public let byteCount: Int
    public let language: String
    public let role: String
    public init(id: String, sha256: String, byteCount: Int, language: String, role: String) { self.id = id; self.sha256 = sha256; self.byteCount = byteCount; self.language = language; self.role = role }
}
