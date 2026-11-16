@testable import formal
import Foundation
import Testing

struct CommandTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["capture", "generate", "validate", "check", "coverage", "replay"])
    func rejectsUnimplementedCommands(command: String) async {
        let result = await FormalCommand().run(arguments: [command])
        #expect(result.exitCode == 3)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("UNSUPPORTED_OPERATION"))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [["doctor"], ["unknown"], ["--version", "extra"], ["index", "--source", "Inventory.swift"]])
    func rejectsBadArguments(arguments: [String]) async {
        let result = await FormalCommand().run(arguments: arguments)
        #expect(result.exitCode == 2)
        #expect(result.standardOutput.isEmpty)
    }

    @Test(.timeLimit(.minutes(1)))
    func helpStatesActualSupport() async {
        let result = await FormalCommand().run(arguments: ["--help"])
        #expect(result.exitCode == 0)
        #expect(result.standardOutput.contains("not implemented"))
        #expect(result.standardOutput.hasPrefix("formal 0.1.0-bootstrap\n"))
        #expect(result.standardOutput.contains("formal doctor --toolchain-lock"))
        #expect(!result.standardOutput.contains("formal index"))
    }

    @Test(.timeLimit(.minutes(1)))
    func probesActualCompiler() async throws {
        let identity = try await LocalCompilerProbe().probe()
        #expect(!identity.compilerVersion.isEmpty)
        #expect(identity.target.pointerWidthInBits == 64)
    }

    @Test(.timeLimit(.minutes(1)))
    func timeoutDoesNotReturnSuccess() async {
        await #expect(throws: (any Error).self) { try await LocalCompilerProbe(timeoutSeconds: 0.000_001).probe() }
    }

    @Test(.timeLimit(.minutes(1)))
    func outputLimitDoesNotReturnSuccess() async {
        await #expect(throws: (any Error).self) { try await LocalCompilerProbe(maximumOutputBytes: 1).probe() }
    }
    @Test(.timeLimit(.minutes(1)))
    func draftsRequireExplicitFlagAndPreserveExistingOutput() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record("Cleanup failed: \(error)") } }
        let source = directory.appendingPathComponent("input.py")
        try "def f(a: int) -> int:\n    return a + 1\n".write(to: source, atomically: true, encoding: .utf8)
        let output = directory.appendingPathComponent("Generated")
        let arguments = ["translate", "--language", "python", "--source", source.path, "--output", output.path]
        let missingFlag = await FormalCommand().run(arguments: arguments)
        #expect(missingFlag.exitCode == 2)
        #expect(!FileManager.default.fileExists(atPath: output.path))
        let draft = await FormalCommand().run(arguments: arguments + ["--draft-unvalidated"])
        #expect(draft.exitCode == 0)
        #expect(draft.standardOutput.contains("DRAFT_UNVALIDATED"))
        let report = try Data(contentsOf: output.appendingPathComponent("report.json"))
        let duplicate = await FormalCommand().run(arguments: arguments + ["--draft-unvalidated"])
        #expect(duplicate.exitCode == 2)
        #expect(try Data(contentsOf: output.appendingPathComponent("report.json")) == report)
        try "unsupported".write(to: source, atomically: true, encoding: .utf8)
        let invalidOutput = directory.appendingPathComponent("Invalid")
        let invalid = await FormalCommand().run(arguments: ["translate", "--language", "python", "--source", source.path, "--output", invalidOutput.path, "--draft-unvalidated"])
        #expect(invalid.exitCode == 4)
        #expect(invalid.standardError.contains("python:1:"))
        #expect(!FileManager.default.fileExists(atPath: invalidOutput.path))
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(!names.contains { $0.hasPrefix(".formal-") })
    }

}
