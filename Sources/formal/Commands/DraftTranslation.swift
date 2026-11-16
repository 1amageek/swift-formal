import CryptoKit
import FormalCore
import FormalCompiler
import FormalIR
import FormalValidation
import Foundation

struct DraftTranslation {
    let compiler: any SourceCompiling
    init(compiler: any SourceCompiling = ScalarSourceCompiler()) { self.compiler = compiler }

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
        let program = try compiler.compile(source, language: language, moduleID: "Source")
        let files = try LeanEmitter().emit(program) + TLAEmitter().emit(program)
        let decoder = BackendArtifactDecoder()
        guard let lean = files.first(where: { $0.path == "lean/Generated/Program.lean" }),
              let tla = files.first(where: { $0.path == "tla/Program.tla" }) else {
            throw FormalDiagnostic(.integrityMismatch, "Missing emitted program")
        }
        let decodedLean = try decoder.decodeLeanProgram(lean.contents)
        let decodedTLA = try decoder.decodeTLAProgram(tla.contents)
        guard decodedLean == program, decodedTLA == program else { throw FormalDiagnostic(.integrityMismatch, "Actual output differs from IR") }
        let report = DraftTranslationReport(sourceLanguage: language, profile: language.profile,
            assumptions: language.assumptions, sourceSHA256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), functions: program.functions.map(\.symbol))
        let manager = FileManager.default
        let destination = URL(fileURLWithPath: output).standardizedFileURL
        guard !manager.fileExists(atPath: destination.path) else { throw FormalDiagnostic(.invalidArguments, "Output already exists", path: output) }
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".formal-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
        do {
            for file in files {
                let url = temporary.appendingPathComponent(file.path)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
            }
            try data.write(to: temporary.appendingPathComponent("source.txt"))
            let encodedProgram = try ArtifactJSON.encode(program)
            try encodedProgram.write(to: temporary.appendingPathComponent("program.json"))
            let encodedReport = try ArtifactJSON.encode(report)
            try encodedReport.write(to: temporary.appendingPathComponent("report.json"))
            try manager.moveItem(at: temporary, to: destination)
        } catch {
            do { try manager.removeItem(at: temporary) }
            catch let cleanupError { throw FormalDiagnostic(.ioFailure, "Translation failed (\(error)); staging cleanup also failed (\(cleanupError))", path: temporary.path) }
            throw error
        }
        return report
    }
}
