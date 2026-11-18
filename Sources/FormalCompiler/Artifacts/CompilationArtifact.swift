import Darwin
import Foundation
import FormalCore
import FormalIR
import FormalEvidence

public struct CompilationArtifact: Sendable {
    public let source: Data
    public let sourceDocument: DocumentReference
    public let program: IRProgram
    public let files: [GeneratedDocument]
    public let origins: [OriginLink]
    public let metadata: CompilationMetadata
    public let budget: EvidenceReadBudget

    public func write(to destination: URL) async throws -> CompilationArtifactReference {
        let manager = FileManager.default, output = destination.standardizedFileURL
        guard !manager.fileExists(atPath: output.path) else { throw FormalDiagnostic(.invalidArguments,"Output already exists",path: output.path) }
        let temporary = output.deletingLastPathComponent().appendingPathComponent(".formal-artifact-" + UUID().uuidString)
        try manager.createDirectory(at: temporary,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700])
        var writer: EvidenceBundleWriter?
        do {
            var total = source.count
            for file in files {
                try Task.checkCancellation()
                guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains("..") else { throw FormalDiagnostic(.integrityMismatch,"Generated path escapes artifact") }
                let bytes = Data(file.contents.utf8)
                guard bytes.count <= budget.maximumDatabaseBytes - total else { throw FormalEvidenceError.limit("Compilation output") }; total += bytes.count
                let path = temporary.appendingPathComponent(file.path)
                try manager.createDirectory(at: path.deletingLastPathComponent(),withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
                try durable(bytes,to: path)
            }
            try durable(source,to: temporary.appendingPathComponent("source.txt"))
            let programBytes = try ArtifactJSON.encode(program), originBytes = try EvidenceIdentity.encode(origins)
            try durable(programBytes,to: temporary.appendingPathComponent("program.json"))
            let metadataBytes = try EvidenceIdentity.encode(metadata)
            try durable(metadataBytes,to: temporary.appendingPathComponent("report.json"))
            try durable(originBytes,to: temporary.appendingPathComponent("origins.json"))
            let bundle = try EvidenceBundleWriter(root: temporary.appendingPathComponent("evidence"),budget: budget,chunkBytes: min(budget.maximumRecordBytes,budget.maximumPageBytes))
            writer = bundle
            try await bundle.document(sourceDocument,bytes: source)
            for file in files { try await bundle.document(file.reference,bytes: Data(file.contents.utf8)) }
            for origin in origins { try await bundle.origin(origin) }
            try await CompilationIRGraph.write(program,to: bundle,budget: budget)
            let evidence = try await bundle.seal(); writer = nil
            let manifest: [String: String] = ["layout":"2", "metadataSHA256":EvidenceIdentity.digest(metadataBytes), "programSHA256":EvidenceIdentity.digest(programBytes), "originsSHA256":EvidenceIdentity.digest(originBytes), "sourceSHA256":sourceDocument.sha256, "evidenceSHA256":evidence.sha256]
            let manifestBytes = try EvidenceIdentity.encode(manifest)
            try durable(manifestBytes,to: temporary.appendingPathComponent("compilation.json"))
            try durable(EvidenceIdentity.encode(evidence),to: temporary.appendingPathComponent("evidence.json"))
            var directories = Set([temporary.path])
            for file in files {
                var path = temporary.appendingPathComponent(file.path).deletingLastPathComponent()
                while path.path.hasPrefix(temporary.path) { directories.insert(path.path); path.deleteLastPathComponent() }
            }
            for path in directories.sorted(by: { $0.count > $1.count }) { try sync(URL(fileURLWithPath: path)) }
            try Task.checkCancellation()
            try manager.moveItem(at: temporary,to: output); try sync(output.deletingLastPathComponent())
            return CompilationArtifactReference(sha256: EvidenceIdentity.digest(manifestBytes),evidence: evidence)
        } catch {
            if let writer { do { try await writer.shutdown() } catch let cleanup { throw FormalEvidenceError.io("Compilation failed: \(error); writer cleanup failed: \(cleanup)") } }
            do { if manager.fileExists(atPath: temporary.path) { try manager.removeItem(at: temporary) } }
            catch let cleanup { throw FormalEvidenceError.io("Compilation failed: \(error); staging cleanup failed: \(cleanup)") }
            throw error
        }
    }
    private func durable(_ bytes: Data,to path: URL) throws {
        try bytes.write(to: path); try FileManager.default.setAttributes([.posixPermissions: 0o600],ofItemAtPath: path.path)
        let handle = try FileHandle(forWritingTo: path)
        do { try handle.synchronize(); try handle.close() }
        catch { do { try handle.close() } catch let cleanup { throw FormalEvidenceError.io("Sync failed: \(error); close failed: \(cleanup)") }; throw error }
    }
    private func sync(_ path: URL) throws {
        let descriptor = Darwin.open(path.path,O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw FormalEvidenceError.io("Cannot open artifact directory") }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw FormalEvidenceError.io("Cannot sync artifact directory") }
    }
}
