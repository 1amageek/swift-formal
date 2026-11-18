public protocol SourceCompiling: Sendable {
    func compile(_ request: SourceCompilationRequest) throws -> SourceCompilation
}
