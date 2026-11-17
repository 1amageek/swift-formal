import CryptoKit
import FormalCore
import FormalCompiler
import FormalIR
import FormalValidation
import Foundation

struct DraftTranslation {
    let compiler: any SourceCompiling
    let defaultNumeric: SourceNumericDefault
    init(compiler: (any SourceCompiling)? = nil, defaultNumeric: SourceNumericDefault = .number) {
        self.compiler = compiler ?? ScalarSourceCompiler(defaultNumeric: defaultNumeric)
        self.defaultNumeric = defaultNumeric
    }

    func perform(source path: String, language: SourceLanguage, output: String) throws -> DraftTranslationReport {
        let sourceURL = URL(fileURLWithPath: path)
        let attributes = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard attributes.isRegularFile == true else { throw FormalDiagnostic(.invalidArguments, "Source must be a regular file", path: path) }
        let handle = try FileHandle(forReadingFrom: sourceURL)
        let data: Data
        do {
            var contents = Data()
            while contents.count <= 1_000_000 {
                let chunk = try handle.read(upToCount: 1_000_001 - contents.count) ?? Data()
                if chunk.isEmpty { break }
                contents.append(chunk)
            }
            data = contents
        } catch {
            do { try handle.close() }
            catch let closeError { throw FormalDiagnostic(.ioFailure, "Read failed (\(error)); close failed (\(closeError))", path: path) }
            throw error
        }
        try handle.close()
        guard data.count <= 1_000_000, let source = String(data: data, encoding: .utf8) else {
            throw FormalDiagnostic(.sourceParseFailed, "Source exceeds 1 MB or is not UTF-8", path: path)
        }
        let artifact = try SourceArtifactGenerator(compiler: compiler, defaultNumeric: defaultNumeric).generate(data, language: language, moduleID: "Source")
        let program = artifact.program
        let files = artifact.files
        let decoder = BackendArtifactDecoder()
        guard let lean = files.first(where: { $0.path == "lean/Generated/Program.lean" }),
              let tla = files.first(where: { $0.path == "tla/Program.tla" }) else {
            throw FormalDiagnostic(.integrityMismatch, "Missing emitted program")
        }
        let decodedLean = try decoder.decodeLeanProgram(lean.contents)
        let decodedTLA = try decoder.decodeTLAProgram(tla.contents)
        guard decodedLean == program, decodedTLA == program else { throw FormalDiagnostic(.integrityMismatch, "Actual output differs from IR") }
        let report = DraftTranslationReport(sourceLanguage: language, profile: language.profile,
            assumptions: language.assumptions, defaultNumeric: language.isJavaScriptFamily ? defaultNumeric : nil, sourceSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), functions: program.functions.map(\.symbol))
        try artifact.write(to: URL(fileURLWithPath: output))
        return report
    }
}
