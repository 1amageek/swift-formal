import Foundation
import FormalCore
import FormalIR

public struct SourceArtifact: Sendable {
    public let source: Data
    public let program: IRProgram
    public let files: [GeneratedFile]
    public let report: SourceArtifactReport

    public func write(to destination: URL) throws {
        let manager = FileManager.default
        let output = destination.standardizedFileURL
        guard !manager.fileExists(atPath: output.path) else {
            throw FormalDiagnostic(.invalidArguments, "Output already exists", path: output.path)
        }
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".formal-artifact-\(UUID().uuidString)")
        try manager.createDirectory(at: temporary, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        do {
            for file in files {
                guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else {
                    throw FormalDiagnostic(.integrityMismatch, "Generated artifact path escapes output")
                }
                let url = temporary.appendingPathComponent(file.path)
                try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.write(to: url, atomically: true, encoding: .utf8)
            }
            try source.write(to: temporary.appendingPathComponent("source.txt"))
            let programBytes = try ArtifactJSON.encode(program)
            try programBytes.write(to: temporary.appendingPathComponent("program.json"))
            let reportBytes = try ArtifactJSON.encode(report)
            try reportBytes.write(to: temporary.appendingPathComponent("report.json"))
            try manager.moveItem(at: temporary, to: output)
        } catch {
            do { try manager.removeItem(at: temporary) }
            catch let cleanup { throw FormalDiagnostic(.ioFailure, "Generation failed (\(error)); staging cleanup failed (\(cleanup))", path: temporary.path) }
            throw error
        }
    }
}
