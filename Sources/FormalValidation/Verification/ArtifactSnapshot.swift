import Foundation
import FormalCore
import FormalIR

struct ArtifactSnapshot {
    let program: IRProgram
    let files: [String: Data]
    let hashes: [String: String]

    init(_ root: URL) throws {
        guard let trustURL = Bundle.module.url(forResource: "trusted-artifacts", withExtension: "json") else {
            throw FormalDiagnostic(.ioFailure, "Missing trusted runtime policy")
        }
        let trust = try ArtifactJSON.read([String: String].self, from: trustURL)
        var files: [String: Data] = [:]
        for path in ["program.json", "source.txt", "report.json", "lean/Generated/Program.lean", "tla/Program.tla"] + trust.keys.sorted() {
            let url = root.appendingPathComponent(path)
            guard url.resolvingSymlinksInPath().path.hasPrefix(root.resolvingSymlinksInPath().path + "/") else {
                throw FormalDiagnostic(.integrityMismatch, "Artifact escapes root")
            }
            files[path] = try ArtifactJSON.readBytes(from: url, maximumBytes: 16_777_216)
        }
        var hashes: [String: String] = [:]
        for (path, data) in files { hashes[path] = FileDigest.sha256(data) }
        for (path, hash) in trust {
            guard hashes[path] == hash else { throw FormalDiagnostic(.integrityMismatch, "Trusted runtime hash mismatch", path: path) }
        }
        let program = try JSONDecoder().decode(IRProgram.self, from: files["program.json"]!)
        try program.validate()
        let decoder = BackendArtifactDecoder()
        let lean = try decoder.decodeLeanProgram(String(decoding: files["lean/Generated/Program.lean"]!, as: UTF8.self))
        let tla = try decoder.decodeTLAProgram(String(decoding: files["tla/Program.tla"]!, as: UTF8.self))
        guard program == lean, program == tla else { throw FormalDiagnostic(.integrityMismatch, "Actual emitted data differs from IR") }
        guard let report = try JSONSerialization.jsonObject(with: files["report.json"]!) as? [String: Any],
              report["sourceSHA256"] as? String == hashes["source.txt"], report["status"] as? String == "DRAFT_UNVALIDATED" else {
            throw FormalDiagnostic(.integrityMismatch, "Invalid draft provenance")
        }
        self.program = program; self.files = files; self.hashes = hashes
    }
    func write(to root: URL) throws {
        for (path, data) in files where path.hasPrefix("lean/") || path.hasPrefix("tla/") {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }
}
