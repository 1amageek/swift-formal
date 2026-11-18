public protocol FormalInspecting: Sendable {
    func inspect(_ request: FormalInspectionRequest) async throws -> FormalInspectionResult
}
