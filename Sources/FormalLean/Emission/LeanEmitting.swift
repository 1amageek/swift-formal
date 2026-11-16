import FormalCore
import FormalIR

public protocol LeanEmitting: Sendable {
    func emit(_ program: IRProgram) throws -> [GeneratedFile]
}
