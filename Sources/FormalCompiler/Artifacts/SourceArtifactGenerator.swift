import CryptoKit
import Foundation
import FormalCore

public struct SourceArtifactGenerator: SourceArtifactGenerating {
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
    public func generate(_ source: Data, language: SourceLanguage, moduleID: String = "Source") throws -> SourceArtifact {
        guard source.count <= 1_000_000, let text = String(data: source, encoding: .utf8), !moduleID.isEmpty else {
            throw FormalDiagnostic(.sourceParseFailed, "Source must be UTF-8 within 1 MB and have an explicit module identity")
        }
        let program = try compiler.compile(text, language: language, moduleID: moduleID)
        try program.validate()
        let lean = try LeanEmitter().emit(program)
        let tla = try TLAEmitter().emit(program)
        let report = SourceArtifactReport(schemaVersion: 1, status: "DRAFT_UNVALIDATED", sourceLanguage: language,
            profile: language.profile, assumptions: language.assumptions,
            defaultNumeric: language.isJavaScriptFamily ? defaultNumeric : nil,
            sourceSHA256: SHA256.hash(data: source).map { String(format: "%02x", $0) }.joined(),
            functions: program.functions.map(\.symbol), actualOutputDataMatchesIR: false,
            semanticValidationPerformed: false, externalToolsExecuted: false)
        return SourceArtifact(source: source, program: program, files: lean + tla, report: report)
    }
}
