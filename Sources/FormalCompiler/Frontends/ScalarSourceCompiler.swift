import FormalIR

public struct ScalarSourceCompiler: SourceCompiling {
    public let maximumSourceBytes: Int
    public let maximumTokens: Int
    public let maximumNesting: Int
    public let defaultNumeric: SourceNumericDefault
    public init(maximumSourceBytes: Int = 1_000_000, maximumTokens: Int = 100_000, maximumNesting: Int = 128, defaultNumeric: SourceNumericDefault = .number) {
        self.maximumSourceBytes = maximumSourceBytes
        self.maximumTokens = maximumTokens
        self.maximumNesting = maximumNesting
        self.defaultNumeric = defaultNumeric
    }
    // FIXME(INCOMPLETE_IMPLEMENTATION): The production draft command calls this restricted source frontend.
    // General language constructs and independent source-to-IR certification remain incomplete.
    // Do not advertise full language support or VALIDATED output until those acceptance conditions are met.
    public func compile(_ source: String, language: SourceLanguage, moduleID: String) throws -> IRProgram {
        let tokens = try SourceLexer.tokenize(source, language: language, maximumBytes: maximumSourceBytes, maximumTokens: maximumTokens)
        var parser = SourceParser(language: language, tokens: tokens, maximumNesting: maximumNesting)
        let parsed = try parser.parse()
        var resolver = SourceTypeResolver(language: language, defaultNumeric: defaultNumeric)
        let functions = try resolver.resolve(parsed)
        var lowering = SourceLowering(language: language, moduleID: moduleID, functions: functions)
        return try lowering.lower()
    }
}
