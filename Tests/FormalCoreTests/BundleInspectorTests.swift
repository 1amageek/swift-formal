import FormalCore
import Foundation
import Testing

struct BundleInspectorTests {
    @Test(.timeLimit(.minutes(1)))
    func integrityDoesNotClaimSemanticValidation() throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        let result = try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock)
        #expect(result.integrityChecked)
        #expect(!result.semanticValidationPerformed)
        #expect(result.moduleCount == 1)
        let first = try ArtifactJSON.encode(result)
        let second = try ArtifactJSON.encode(result)
        #expect(first == second)
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsTampering() throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        try Data("modified".utf8).write(to: fixture.root.appendingPathComponent("modules/Main.sil"))
        do {
            _ = try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock)
            Issue.record("Modified SIL was accepted.")
        } catch let error as FormalDiagnostic { #expect(error.code == .integrityMismatch) }
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["../outside.sil", "/tmp/outside.sil", "modules/../outside.sil", "modules//Main.sil"])
    func rejectsEscapingPaths(path: String) throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        try fixture.mutate("manifest.json") {
            var modules = $0["modules"] as! [[String: Any]]
            modules[0]["path"] = path
            $0["modules"] = modules
        }
        #expect(throws: FormalDiagnostic.self) { try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock) }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsSymlinkEscape() throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        let path = fixture.root.appendingPathComponent("modules/Main.sil")
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: URL(fileURLWithPath: "/etc/hosts"))
        #expect(throws: FormalDiagnostic.self) { try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock) }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsMissingContextAndRawSIL() throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        try fixture.mutate("build-context.json") { $0["silStage"] = "raw" }
        #expect(throws: FormalDiagnostic.self) { try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock) }
        try fixture.mutate("build-context.json") { $0.removeValue(forKey: "dataLayout") }
        #expect(throws: FormalDiagnostic.self) { try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock) }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsMissingClosureAndEntryPoints() throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        try fixture.mutate("manifest.json") {
            var modules = $0["modules"] as! [[String: Any]]
            modules[0]["dependencies"] = ["Missing"]
            $0["modules"] = modules
        }
        #expect(throws: FormalDiagnostic.self) { try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock) }
        try fixture.mutate("manifest.json") { $0["entryPoints"] = [] }
        #expect(throws: FormalDiagnostic.self) { try BundleInspector().inspect(at: fixture.root, expectedLock: fixture.lock) }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsResourceLimitsAndEnablingGeneration() throws {
        let fixture = try BundleFixture()
        defer { fixture.cleanup() }
        #expect(throws: FormalDiagnostic.self) {
            try BundleInspector(maximumBundleBytes: 1).inspect(at: fixture.root, expectedLock: fixture.lock)
        }
        try fixture.mutate("toolchain.lock.json") { $0["generationSupported"] = true }
        let lock = try ArtifactJSON.read(ToolchainLock.self, from: fixture.root.appendingPathComponent("toolchain.lock.json"))
        #expect(throws: FormalDiagnostic.self) { try lock.validate() }
    }
}
