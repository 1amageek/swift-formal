public struct SourceIndex: Codable, Sendable, Equatable {
    public struct Declaration: Codable, Sendable, Equatable {
        public let name: String
        public let kind: String
        public let startLine: Int?
        public let endLine: Int?
    }

    public let path: String
    public let declarations: [Declaration]
    public let providesExecutionSemantics: Bool
    public let completeDeclarationCoverage: Bool
    public let limitations: [String]

    init(path: String, declarations: [Declaration]) {
        self.path = path
        self.declarations = declarations
        self.providesExecutionSemantics = false
        self.completeDeclarationCoverage = false
        self.limitations = ["The fixed upstream index can omit same-line members; missing declarations do not exclude SIL semantics."]
    }
}
