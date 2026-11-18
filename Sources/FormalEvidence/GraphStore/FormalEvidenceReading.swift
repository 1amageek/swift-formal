public protocol FormalEvidenceReading: Sendable {
    func catalog() async throws -> EvidenceCatalog
    func graph(_ query: FormalGraphQuery) async throws -> FormalGraphPage
    func trace(_ query: FormalTraceQuery) async throws -> FormalTracePage
    func origins(_ query: OriginQuery) async throws -> OriginPage
    func document(_ query: DocumentRangeQuery) async throws -> DocumentChunk
    func shutdown() async throws
}
