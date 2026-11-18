import FormalIR
import FormalEvidence

public struct SourceCompilation: Sendable {
    public let program: IRProgram
    public let sourceDocument: DocumentReference
    public let origins: [OriginLink]
    public let defaultNumeric: SourceNumericDefault
}
