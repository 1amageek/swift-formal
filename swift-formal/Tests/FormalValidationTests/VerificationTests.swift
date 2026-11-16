import Foundation
import FormalCore
import FormalIR
import FormalCompiler
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
    func snapshotAuditsActualRuntimeAndEmittedData() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Cleanup: \(error)") } }
        let source = "def f(a: int) -> int:\n    return a + 1\n"
        let data = Data(source.utf8)
        let program = try ScalarSourceCompiler().compile(source, language: .python, moduleID: "Source")
        let files = try LeanEmitter().emit(program) + TLAEmitter().emit(program)
        for file in files {
            let path = root.appendingPathComponent(file.path)
            try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
            try file.contents.write(to: path, atomically: true, encoding: .utf8)
        }
        try data.write(to: root.appendingPathComponent("source.txt"))
        let encoded = try ArtifactJSON.encode(program)
        try encoded.write(to: root.appendingPathComponent("program.json"))
        let provenance = try ArtifactJSON.encode(["status":"DRAFT_UNVALIDATED","sourceSHA256":FileDigest.sha256(data)])
        try provenance.write(to: root.appendingPathComponent("report.json"))
        #expect(try ArtifactSnapshot(root).program == program)
        let runtime = root.appendingPathComponent("lean/SwiftFormal/Runtime.lean")
        try "arbitrary Lean".write(to: runtime, atomically: true, encoding: .utf8)
        #expect(throws: (any Error).self) { try ArtifactSnapshot(root) }
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
