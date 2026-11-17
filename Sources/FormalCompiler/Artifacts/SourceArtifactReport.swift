public struct SourceArtifactReport: Codable, Sendable {
    public let schemaVersion: Int
    public let status: String
    public let sourceLanguage: SourceLanguage
    public let profile: String
    public let assumptions: [String]
    public let defaultNumeric: SourceNumericDefault?
    public let sourceSHA256: String
    public let functions: [String]
    public let actualOutputDataMatchesIR: Bool
    public let semanticValidationPerformed: Bool
    public let externalToolsExecuted: Bool
}
