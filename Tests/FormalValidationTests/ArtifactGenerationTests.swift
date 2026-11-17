import Foundation
import Testing
import FormalCore
import FormalIR
import FormalCompiler
import FormalValidation

struct ArtifactGenerationTests {
    @Test(.timeLimit(.minutes(1))) func generatesAuditableExactSourceWithoutClaimingValidation() throws {
        #expect(try SourceArtifactGenerator.resourceIdentity().count == 64)
        let bytes = Data("func calculate(_ a: Int64) -> Int64 { return a + 1 }\n".utf8)
        let artifact = try SourceArtifactGenerator().generate(bytes, language: .swift, moduleID: "Source")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        try artifact.write(to: root)
        #expect(try Data(contentsOf: root.appendingPathComponent("source.txt")) == bytes)
        let decoder = BackendArtifactDecoder()
        let lean = try String(contentsOf: root.appendingPathComponent("lean/Generated/Program.lean"), encoding: .utf8)
        #expect(try decoder.decodeLeanProgram(lean) == artifact.program)
        let observed = try IRInterpreter(fuel: 64).run(artifact.program, entry: "calculate", arguments: [.bits(try BitPattern(width: 64, bits: 8))])
        #expect(observed.outcome == .returned(.bits(try BitPattern(width: 64, bits: 9))))
        #expect(artifact.report.status == "DRAFT_UNVALIDATED")
        #expect(!artifact.report.semanticValidationPerformed)
        #expect(throws: (any Error).self) { try artifact.write(to: root) }
        #expect(try Data(contentsOf: root.appendingPathComponent("source.txt")) == bytes)
    }
    @Test(.timeLimit(.minutes(1))) func rejectsIncompleteSourceBeforePublishing() throws {
        for source in [Data([0xff]), Data("actor Store {}".utf8), Data(repeating: 65, count: 1_000_001)] {
            #expect(throws: (any Error).self) { try SourceArtifactGenerator().generate(source, language: .swift, moduleID: "Source") }
        }
    }
}
