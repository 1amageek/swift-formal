import Foundation
import FormalCore
import FormalIR
import FormalCompiler
import FormalEvidence
@testable import FormalValidation
import Testing

struct VerificationTests {
    @Test(.timeLimit(.minutes(1)))
    func scenarioRejectsUnknownFieldsAndInvalidBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Cleanup: \(error)") } }
        let path = root.appendingPathComponent("scenario.json")
        let base = """
        {"schemaVersion":1,"fuel":128,"cases":[{"name":"a","entry":"f","arguments":["2"],"expected":{"status":"returned","value":"3"}}]}
        """
        try base.write(to: path, atomically: true, encoding: .utf8)
        let valid = try VerificationScenario.load(path)
        #expect(valid.cases.count == 1)
        for changed in [base.replacingOccurrences(of: "128", with: "0"), base.replacingOccurrences(of: "\"fuel\"", with: "\"typo\""), base.replacingOccurrences(of: "\"name\":\"a\"", with: "\"name\":\"../bad\""), base.replacingOccurrences(of: "\"value\":\"3\"", with: "\"value\":\"3\",\"ignored\":true")] {
            try changed.write(to: path, atomically: true, encoding: .utf8)
            #expect(throws: (any Error).self) { try VerificationScenario.load(path) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func snapshotAuditsLayoutOriginsRuntimeAndEmittedData() async throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: parent) } catch { Issue.record("Cleanup: \(error)") } }
        let source = Data("# α comment\ndef f(a: int) -> int:\n    return a + 1\n".utf8)
        let artifact = try CompilationArtifactGenerator().generate(CompilationRequest(source: source,language: .python,moduleID: "Audit",evidenceBudget: ArtifactGenerationTests.budget))
        let pristine = parent.appendingPathComponent("pristine")
        _ = try await artifact.write(to: pristine)
        #expect(try await ArtifactSnapshot(pristine).program == artifact.program)
        for mutation in ["oldLayout","originRange","originAddress","missingEvidence","runtime","source","metadata"] {
            let root = parent.appendingPathComponent(mutation)
            try FileManager.default.copyItem(at: pristine,to: root)
            if mutation == "oldLayout" { try FileManager.default.removeItem(at: root.appendingPathComponent("compilation.json")) }
            if mutation == "missingEvidence" { try FileManager.default.removeItem(at: root.appendingPathComponent("evidence")) }
            if mutation == "runtime" { try Data("arbitrary Lean".utf8).write(to: root.appendingPathComponent("lean/SwiftFormal/Runtime.lean")) }
            if mutation == "metadata" {
                let path = root.appendingPathComponent("report.json")
                let bytes = try Data(contentsOf: path)
                let object = try JSONSerialization.jsonObject(with: bytes)
                var metadata = try #require(object as? [String:Any])
                metadata["assumptions"] = ["forged assumption"]
                let altered = try JSONSerialization.data(withJSONObject: metadata,options: [.sortedKeys])
                try altered.write(to: path)
            }
            if mutation == "source" { try Data("changed source".utf8).write(to: root.appendingPathComponent("source.txt")) }
            if mutation == "originRange" || mutation == "originAddress" {
                let original = try #require(artifact.origins.first { $0.source != nil && $0.address != nil })
                let range = try #require(original.source), address = try #require(original.address)
                let changed = OriginLink(id: original.id,source: mutation == "originRange" ? TextRange(documentID: range.documentID,start: 3,end: 4) : range,
                    address: mutation == "originAddress" ? IRAddress(programDigest: address.programDigest,function: address.function,block: "missing",instruction: 999) : address,
                    generated: original.generated,precision: original.precision,producer: original.producer,synthetic: original.synthetic)
                let origins = artifact.origins.map { $0.id == original.id ? changed : $0 }
                let bytes = try EvidenceIdentity.encode(origins)
                try bytes.write(to: root.appendingPathComponent("origins.json"))
                let manifestURL = root.appendingPathComponent("compilation.json")
                let manifestBytes = try Data(contentsOf: manifestURL)
                var manifest = try JSONDecoder().decode([String:String].self,from: manifestBytes)
                manifest["originsSHA256"] = EvidenceIdentity.digest(bytes)
                let updated = try EvidenceIdentity.encode(manifest)
                try updated.write(to: manifestURL)
            }
            await #expect(throws: (any Error).self, "Accepted mutation: \(mutation)") { try await ArtifactSnapshot(root) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func corruptCachedArchiveFailsBeforeExtractionOrDownload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Cleanup: \(error)") } }
        let cache = root.appendingPathComponent("cache")
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: false)
        try Data("corrupt".utf8).write(to: cache.appendingPathComponent("lean-4.35.0-darwin_aarch64.zip"))
        do {
            _ = try await PinnedToolchain().prepare(at: root.appendingPathComponent("tools"), cache: cache)
            Issue.record("Corrupt archive was accepted")
        } catch let error as FormalDiagnostic { #expect(error.code == .integrityMismatch) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).sorted() == ["cache"])
    }

    @Test(.timeLimit(.minutes(1)))
    func inventoryUsesRelativePathsAcrossMacOSTemporaryAliases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Cleanup: \(error)") } }
        let file = root.appendingPathComponent("file")
        try Data("payload".utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: "file")
        let hash = FileDigest.sha256(Data("payload".utf8))
        let expected = FileDigest.sha256(Data("F\tfile\t0\t7\t\(hash)\nL\tlink\tfile\n".utf8))
        #expect(try FileDigest.inventory(root) == expected)
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("escape").path, withDestinationPath: "/usr/bin/true")
        #expect(throws: (any Error).self) { try FileDigest.inventory(root) }
    }

    @Test(.timeLimit(.minutes(1)))
    func axiomAuditRejectsAdmissionsAndCustomAxioms() throws {
        let allowed = ["propext", "Classical.choice", "Quot.sound"]
        #expect(try LeanProofAudit.check("'checkedCase' does not depend on any axioms\n", allowed: allowed).isEmpty)
        #expect(try LeanProofAudit.check("'checkedCase' depends on axioms: [propext, Classical.choice, Quot.sound]", allowed: allowed).count == 3)
        for output in ["'checkedCase' depends on axioms: [sorryAx]", "'checkedCase' depends on axioms: [custom]", "", "'other' does not depend on any axioms"] {
            #expect(throws: (any Error).self) { try LeanProofAudit.check(output, allowed: allowed) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func scalarBitInputsEnforceWidthAndSignedRange() throws {
        #expect(try ScalarCase.value("-1", type: .bits(width: 64)) == .bits(BitPattern(width: 64, bits: .max)))
        #expect(throws: (any Error).self) { try ScalarCase.value("-2", type: .bits(width: 1)) }
        #expect(throws: (any Error).self) { try ScalarCase.value("256", type: .bits(width: 8)) }
        #expect(throws: (any Error).self) { try ScalarCase.value("01", type: .integer) }
    }
}
