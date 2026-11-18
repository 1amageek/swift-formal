import Foundation

public struct InspectionInputFile: Codable, Sendable, Equatable {
    public let path: String
    public let sha256: String
    public let byteCount: Int
    public init(path: String, sha256: String, byteCount: Int) { self.path = path; self.sha256 = sha256; self.byteCount = byteCount }
}
