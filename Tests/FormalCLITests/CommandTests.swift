@testable import formal
import Foundation
import Testing

struct CommandTests {
    @Test(.timeLimit(.minutes(1)), arguments: [
        "func optional(_ value: Int64?) -> Bool { value != nil }",
        "func text() -> String { \"name\" }",
        "func wrapping(_ value: Int64) -> Int64 { value &+ 1 }",
        "func bits(_ value: Int64) -> Int64 { value | 1 }",
        "func shifted(_ value: Int64) -> Int64 { value << 1 }",
        "func escaped() -> String { #\"raw\"# }",
        "func file() -> String { #fileID }",
        "func unicode(_ café: Int64) -> Int64 { café }",
        "func escapedName(_ `default`: Int64) -> Int64 { `default` }",
        "func closure(_ body: () -> Bool) -> Bool { body() }"
    ])
    func swiftProfileGapsAreNotSyntaxFailures(_ source: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
        let file = directory.appendingPathComponent("Input.swift"), output = directory.appendingPathComponent("artifact")
        try Data(source.utf8).write(to: file)
        let result = await FormalCommand().run(arguments: ["translate","--language","swift","--source",file.path,"--output",output.path,"--draft-unvalidated"])
        #expect(result.exitCode == 3)
        #expect(result.standardOutput.isEmpty)
        #expect(result.standardError.contains("UNSUPPORTED_SOURCE_PROFILE"))
        #expect(result.standardError.contains("swift:1:"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == ["Input.swift"])
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        "func broken(_ value: Int64) -> Int64 { return value + }",
        "func broken(_ value: Int64) -> Int64 { return value",
        "func broken(_ value: ) -> Int64 { return 0 }",
        "func broken(_ value: return) -> Int64 { return 0 }",
        "func broken(_ value: Int64) -> Int64 { /* unfinished"
    ])
    func malformedScalarSyntaxStillFailsParsing(_ source: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
        let file = directory.appendingPathComponent("Invalid.swift"), output = directory.appendingPathComponent("artifact")
        try Data(source.utf8).write(to: file)
        let result = await FormalCommand().run(arguments: ["translate","--language","swift","--source",file.path,"--output",output.path,"--draft-unvalidated"])
        #expect(result.exitCode == 4)
        #expect(result.standardError.contains("SOURCE_PARSE_FAILED"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(.timeLimit(.minutes(1))) func swiftArrayIsDiagnosedAsOutsideScalarProfile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: directory) } catch { Issue.record(error) } }
        let file = directory.appendingPathComponent("Rows.swift")
        try Data("struct Rows { let values: [Int] }".utf8).write(to: file)
        let output = directory.appendingPathComponent("artifact")
        let result = await FormalCommand().run(arguments: ["translate","--language","swift","--source",file.path,"--output",output.path,"--draft-unvalidated"])
        #expect(result.exitCode == 3)
        #expect(result.standardError.contains("UNSUPPORTED_SOURCE_PROFILE"))
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }
    @Test(.timeLimit(.minutes(1)), arguments: ["capture", "generate", "validate", "coverage", "replay"])
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
        #expect(result.standardOutput.hasPrefix("formal 0.4.0\n"))
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
