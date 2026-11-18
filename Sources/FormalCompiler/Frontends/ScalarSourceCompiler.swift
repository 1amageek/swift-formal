import Foundation
import FormalIR
import FormalEvidence
import FormalCore

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
    public func compile(_ request: SourceCompilationRequest) throws -> SourceCompilation {
        try Task.checkCancellation()
        guard let source = String(data: request.source, encoding: .utf8) else { throw FormalDiagnostic(.sourceParseFailed, "Source is not UTF-8") }
        let language = request.language, moduleID = request.moduleID
        let numeric = request.defaultNumeric ?? defaultNumeric
        let tokens = try SourceLexer.tokenize(source, language: language, maximumBytes: maximumSourceBytes, maximumTokens: maximumTokens)
        var parser = SourceParser(language: language, tokens: tokens, maximumNesting: maximumNesting)
        let parsed = try parser.parse()
        var resolver = SourceTypeResolver(language: language, defaultNumeric: numeric)
        let functions = try resolver.resolve(parsed)
        var lowering = SourceLowering(language: language, moduleID: moduleID, functions: functions)
        let program = try lowering.lower()
        let programBytes = try ArtifactJSON.encode(program), sourceDigest = EvidenceIdentity.digest(request.source)
        let programDigest = EvidenceIdentity.digest(programBytes)
        let document = DocumentReference(id: EvidenceIdentity.id("source-document", sourceDigest, language.rawValue), sha256: sourceDigest, byteCount: request.source.count, language: language.rawValue, role: "original")
        let origins = lowering.locations.enumerated().map { index, location in
            OriginLink(id: EvidenceIdentity.id("source-origin",programDigest,String(index)), source: location.range.map { TextRange(documentID: document.id, start: $0.start, end: $0.end) }, address: IRAddress(programDigest: programDigest, function: location.function, block: location.block, instruction: location.instruction), generated: nil, precision: location.range == nil ? "unavailable" : location.precision, producer: language.profile, synthetic: location.instruction != nil)
        }
        return SourceCompilation(program: program, sourceDocument: document, origins: origins, defaultNumeric: numeric)
    }
}
