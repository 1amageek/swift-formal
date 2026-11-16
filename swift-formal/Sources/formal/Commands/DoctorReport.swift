import FormalCore

struct DoctorReport: Encodable {
    let profileID: String
    let compilerIdentityMatches: Bool
    let compiler: CompilerIdentity
    let generationSupported = false
    let semanticValidationAvailable = false
    let note = "Compiler identity only; SDK, runtime semantics, Lean, and TLA tools are not certified."

    init(lock: ToolchainLock, compiler: CompilerIdentity) throws {
        try lock.validate()
        guard compiler.compilerVersion == lock.compilerVersion,
              compiler.swiftCompilerTag == lock.compilerTag,
              compiler.target.triple == lock.targetTriple,
              compiler.target.pointerWidthInBits == lock.pointerWidth else {
            throw FormalDiagnostic(.toolchainMismatch, "Active compiler identity differs from the toolchain lock.")
        }
        self.profileID = lock.profileID
        self.compilerIdentityMatches = true
        self.compiler = compiler
    }
}
