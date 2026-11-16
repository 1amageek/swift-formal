public protocol IRExecuting: Sendable {
    func run(_ program: IRProgram, entry: String, arguments: [IRValue]) throws -> IRExecutionResult
}
