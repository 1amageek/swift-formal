public enum FormalEvidenceError: Error, Sendable, Equatable, CustomStringConvertible {
    case invalid(String), integrity(String), limit(String), missing(String), unsupported(String), io(String)
    case closed, incompatibleVersion, invalidCursor
    public var description: String { switch self { case .invalid(let s): "INVALID: " + s; case .integrity(let s): "INTEGRITY: " + s; case .limit(let s): "LIMIT: " + s; case .missing(let s): "MISSING: " + s; case .unsupported(let s): "UNSUPPORTED: " + s; case .io(let s): "IO: " + s; case .closed: "CLOSED"; case .incompatibleVersion: "INCOMPATIBLE_VERSION"; case .invalidCursor: "INVALID_CURSOR" } }
}
