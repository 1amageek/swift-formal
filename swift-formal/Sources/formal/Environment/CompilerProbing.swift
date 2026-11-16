public protocol CompilerProbing: Sendable {
    func probe() async throws -> CompilerIdentity
}
