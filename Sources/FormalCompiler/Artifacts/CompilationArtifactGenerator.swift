import CryptoKit
import Foundation
import FormalCore
import FormalEvidence

public struct CompilationArtifactGenerator: CompilationArtifactGenerating {
    private let compiler: any SourceCompiling
    private let defaultNumeric: SourceNumericDefault
    public init(compiler: (any SourceCompiling)? = nil, defaultNumeric: SourceNumericDefault = .number) {
        self.compiler = compiler ?? ScalarSourceCompiler(defaultNumeric: defaultNumeric)
        self.defaultNumeric = defaultNumeric
    }
    public static func resourceIdentity() throws -> String {
        var values: [String: String] = [:]
        for (name, ext) in [("Runtime", "lean"), ("SwiftFormalRuntime", "tla")] {
            guard let url = Bundle.module.url(forResource: name, withExtension: ext) else { throw FormalDiagnostic(.ioFailure, "Missing compiler runtime resource") }
            let bytes = try ArtifactJSON.readBytes(from: url, maximumBytes: 1_000_000)
            values[name + "." + ext] = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(values)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    public func generate(_ request: CompilationRequest) throws -> CompilationArtifact {
        let compilation = try compiler.compile(SourceCompilationRequest(source: request.source, language: request.language, moduleID: request.moduleID, defaultNumeric: defaultNumeric))
        let program = compilation.program
        let lean = try LeanEmitter().emit(program)
        let tla = try TLAEmitter().emit(program)
        let metadata = CompilationMetadata(schemaVersion: 2, status: "DRAFT_UNVALIDATED", sourceLanguage: request.language,
            profile: request.language.profile, assumptions: request.language.assumptions,
            defaultNumeric: request.language.isJavaScriptFamily ? compilation.defaultNumeric : nil,
            sourceSHA256: compilation.sourceDocument.sha256, functions: program.functions.map(\.symbol))
        var indexed: [IRAddress: OriginLink] = [:]
        for origin in compilation.origins { if let address = origin.address { indexed[address] = origin } }
        let emitted = (lean + tla).flatMap(\.origins).map { value in
            let source = value.address.flatMap { indexed[$0] }
            return OriginLink(id: value.id,source: source?.source,address: value.address,generated: value.generated,precision: source?.precision ?? "unavailable",producer: value.producer,synthetic: source?.synthetic ?? true)
        }
        return CompilationArtifact(source: request.source, sourceDocument: compilation.sourceDocument, program: program, files: lean + tla,
            origins: compilation.origins + emitted, metadata: metadata, budget: request.evidenceBudget)
    }
}
