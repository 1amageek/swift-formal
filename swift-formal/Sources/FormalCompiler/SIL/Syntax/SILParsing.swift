public protocol SILParsing: Sendable {
    func parse(_ source: String, path: String) throws -> SILModuleSyntax
}
