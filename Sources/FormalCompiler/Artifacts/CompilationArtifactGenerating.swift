public protocol CompilationArtifactGenerating: Sendable {
    func generate(_ request: CompilationRequest) throws -> CompilationArtifact
}
