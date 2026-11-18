import FormalCore
import FormalIR

public protocol TLAEmitting: Sendable {
    func emit(_ program: IRProgram) throws -> [GeneratedDocument]
}
