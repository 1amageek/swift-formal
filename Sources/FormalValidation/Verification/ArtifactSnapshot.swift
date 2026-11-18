import Foundation
import FormalCore
import FormalIR
import FormalEvidence

struct ArtifactSnapshot {
    let program: IRProgram
    let files: [String: Data]
    let hashes: [String: String]
    let compilation: ArtifactReference
    let evidence: EvidenceBundleReference

    init(_ root: URL) async throws {
        guard let trustURL = Bundle.module.url(forResource: "trusted-artifacts", withExtension: "json") else {
            throw FormalDiagnostic(.ioFailure, "Missing trusted runtime policy")
        }
        let trust = try ArtifactJSON.read([String: String].self, from: trustURL)
        var files: [String: Data] = [:]
        let paths = ["compilation.json", "evidence.json", "origins.json", "program.json", "source.txt", "report.json", "lean/Generated/Program.lean", "tla/Program.tla", "lean/lean-toolchain", "lean/lakefile.toml", "lean/Generated/Properties.lean", "lean/Generated.lean", "tla/Properties.tla"] + trust.keys.sorted()
        for path in paths {
            var url = root
            for component in path.split(separator: "/") {
                url.appendPathComponent(String(component))
                let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
                guard values.isSymbolicLink != true else { throw Self.invalid("Symlink artifact", path: path) }
            }
            files[path] = try ArtifactJSON.readBytes(from: url, maximumBytes: 16_777_216)
        }
        var hashes: [String: String] = [:]
        for (path, data) in files { hashes[path] = FileDigest.sha256(data) }
        for (path, hash) in trust {
            guard hashes[path] == hash else { throw Self.invalid("Trusted runtime hash mismatch", path: path) }
        }
        let manifest = try JSONDecoder().decode([String: String].self, from: files["compilation.json"]!)
        guard Set(manifest.keys) == ["layout","metadataSHA256","programSHA256","originsSHA256","sourceSHA256","evidenceSHA256"], manifest["layout"] == "2",
            manifest["programSHA256"] == hashes["program.json"], manifest["sourceSHA256"] == hashes["source.txt"],
            manifest["originsSHA256"] == hashes["origins.json"], manifest["metadataSHA256"] == hashes["report.json"] else { throw Self.invalid("Unsupported or inconsistent compilation layout") }
        let evidence = try JSONDecoder().decode(EvidenceBundleReference.self, from: files["evidence.json"]!)
        guard evidence.sha256 == manifest["evidenceSHA256"] else { throw Self.invalid("Compilation evidence binding mismatch") }
        let program = try JSONDecoder().decode(IRProgram.self, from: files["program.json"]!)
        try program.validate()
        let decoder = BackendArtifactDecoder()
        let leanText = String(decoding: files["lean/Generated/Program.lean"]!, as: UTF8.self)
        let tlaText = String(decoding: files["tla/Program.tla"]!, as: UTF8.self)
        let lean = try decoder.decodeLeanProgram(leanText)
        let tla = try decoder.decodeTLAProgram(tlaText)
        guard program == lean, program == tla else { throw Self.invalid("Actual emitted data differs from IR") }
        guard let report = try JSONSerialization.jsonObject(with: files["report.json"]!) as? [String: Any],
            report["schemaVersion"] as? Int == 2, let language = report["sourceLanguage"] as? String,
            report["sourceSHA256"] as? String == hashes["source.txt"], report["status"] as? String == "DRAFT_UNVALIDATED",
            report["functions"] as? [String] == program.functions.map(\.symbol) else { throw Self.invalid("Invalid draft provenance") }
        let origins = try JSONDecoder().decode([OriginLink].self, from: files["origins.json"]!)
        var documents: [String: Data] = [:], references: [String: DocumentReference] = [:]
        for (path, bytes) in files where path == "source.txt" || path.hasPrefix("lean/") || path.hasPrefix("tla/") {
            let digest = hashes[path]!
            let isSource = path == "source.txt"
            let id = isSource ? EvidenceIdentity.id("source-document",digest,language) : EvidenceIdentity.id("generated-document",path,digest)
            let documentLanguage = isSource ? language : path.hasSuffix(".lean") ? "lean" : path.hasSuffix(".tla") ? "tla" : "text"
            documents[id] = bytes
            references[id] = DocumentReference(id: id,sha256: digest,byteCount: bytes.count,language: documentLanguage,role: isSource ? "original" : "generated")
        }
        guard Set(origins.map(\.id)).count == origins.count else { throw Self.invalid("Duplicate origins") }
        for origin in origins {
            guard EvidenceIdentity.validID(origin.id), !origin.producer.isEmpty else { throw Self.invalid("Invalid origin identity") }
            for range in [origin.source,origin.generated].compactMap({ $0 }) {
                guard let bytes = documents[range.documentID], range.start >= 0, range.end >= range.start, range.end <= bytes.count,
                    [range.start,range.end].allSatisfy({ $0 == bytes.count || bytes[$0] & 0xc0 != 0x80 }) else { throw Self.invalid("Origin range does not match exact UTF-8 document") }
            }
            if let range = origin.source, references[range.documentID]?.role != "original" { throw Self.invalid("Source origin points at generated data") }
            if let range = origin.generated, references[range.documentID]?.role != "generated" { throw Self.invalid("Generated origin points at source data") }
            if let address = origin.address {
                guard address.programDigest == hashes["program.json"], let function = program.functions.first(where: { $0.symbol == address.function }) else { throw Self.invalid("Origin references unknown program/function") }
                if let blockID = address.block {
                    guard let block = function.blocks.first(where: { $0.id == blockID }), address.instruction.map({ block.instructions.indices.contains($0) }) ?? true else { throw Self.invalid("Origin references unknown block/instruction") }
                } else if address.instruction != nil { throw Self.invalid("Origin instruction lacks a block") }
            }
        }
        let budget = EvidenceReadBudget(maximumDatabaseBytes: 536_870_912,maximumRecordBytes: 262_144,maximumPageBytes: 1_048_576,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 8)
        let reader = try await LocalFormalEvidenceStore(root: root.appendingPathComponent("evidence")).open(evidence,budget: budget)
        do {
            let catalog = try await reader.catalog()
            guard catalog.documents.count == references.count, catalog.documents.allSatisfy({ references[$0.id] == $0 }) else { throw Self.invalid("Sealed document catalog differs from compilation") }
            var expected = Dictionary(uniqueKeysWithValues: origins.map { ($0.id,$0) })
            for documentID in references.keys.sorted() + [""] {
                var offset = 0
                while true {
                    let page = try await reader.origins(OriginQuery(documentID: documentID,start: offset,count: budget.maximumNodes))
                    for origin in page.origins {
                        guard expected.removeValue(forKey: origin.id) == origin else { throw Self.invalid("Sealed origin differs from compilation sidecar") }
                    }
                    guard let next = page.nextOffset else { break }; offset = next
                }
            }
            guard expected.isEmpty else { throw Self.invalid("Missing sealed origins") }
            try await reader.shutdown()
        } catch {
            do { try await reader.shutdown() } catch let cleanup { throw Self.invalid("Artifact audit failed (\(error)); evidence close failed (\(cleanup))") }
            throw error
        }
        self.program = program; self.files = files; self.hashes = hashes; self.evidence = evidence
        compilation = ArtifactReference(id: hashes["compilation.json"]!,sha256: hashes["compilation.json"]!,byteCount: files["compilation.json"]!.count,mediaType: "application/json",profile: "formal-compilation/2")
    }
    func write(to root: URL) throws {
        for (path, data) in files where path.hasPrefix("lean/") || path.hasPrefix("tla/") {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }
    private static func invalid(_ message: String,path: String? = nil) -> FormalDiagnostic {
        FormalDiagnostic(.integrityMismatch,message,path: path)
    }
}
