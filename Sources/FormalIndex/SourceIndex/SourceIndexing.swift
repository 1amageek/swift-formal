public protocol SourceIndexing: Sendable {
    func index(source: String, path: String) throws -> SourceIndex
}
