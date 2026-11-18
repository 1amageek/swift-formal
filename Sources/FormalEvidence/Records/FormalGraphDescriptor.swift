import Foundation

public struct FormalGraphDescriptor: Codable, Sendable, Equatable {
    public let id: String
    public let kind: FormalGraphKind
    public let roots: [String]
    public let artifactDigests: [String]
    public let producer: String
    public let scope: String
    public let complete: Bool
    public let extraction: String
    public let diagnostics: [String]
    public init(id: String, kind: FormalGraphKind, roots: [String] = [], artifactDigests: [String], producer: String, scope: String, complete: Bool, extraction: String, diagnostics: [String]) { self.id = id; self.kind = kind; self.roots = roots; self.artifactDigests = artifactDigests; self.producer = producer; self.scope = scope; self.complete = complete; self.extraction = extraction; self.diagnostics = diagnostics }
}
