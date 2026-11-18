import Foundation
import FormalEvidence

public struct GeneratedDocument: Sendable, Equatable {
    public let path: String
    public let contents: String
    public let origins: [OriginLink]
    public init(path: String, contents: String, origins: [OriginLink]) { self.path = path; self.contents = contents; self.origins = origins }
    public var reference: DocumentReference {
        let bytes = Data(contents.utf8), language = path.hasSuffix(".lean") ? "lean" : path.hasSuffix(".tla") ? "tla" : "text"
        let digest = EvidenceIdentity.digest(bytes)
        return DocumentReference(id: EvidenceIdentity.id("generated-document",path,digest), sha256: digest, byteCount: bytes.count, language: language, role: "generated")
    }
}
