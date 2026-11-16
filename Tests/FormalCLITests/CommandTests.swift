import FormalCLI
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

    @Test(.timeLimit(.minutes(1)), arguments: [["doctor"], ["unknown"], ["--version", "extra"], ["index", "--source", "a", "--source", "b"]])
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
}
