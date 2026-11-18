import Foundation
import Testing
import FormalCore
import FormalIR
import FormalCompiler
import FormalValidation
import FormalEvidence

struct ArtifactGenerationTests {
    static let budget = EvidenceReadBudget(maximumDatabaseBytes: 16_777_216,maximumRecordBytes: 262_144,maximumPageBytes: 1_048_576,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 16)
    @Test(.timeLimit(.minutes(1))) func generatesAuditableExactSourceWithoutClaimingValidation() async throws {
        #expect(try CompilationArtifactGenerator.resourceIdentity().count == 64)
        let bytes = Data("func calculate(_ a: Int64) -> Int64 { return a + 1 }\n".utf8)
        let artifact = try CompilationArtifactGenerator().generate(CompilationRequest(source: bytes,language: .swift,moduleID: "Source",evidenceBudget: Self.budget))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        _ = try await artifact.write(to: root)
        #expect(try Data(contentsOf: root.appendingPathComponent("source.txt")) == bytes)
        let decoder = BackendArtifactDecoder()
        let lean = try String(contentsOf: root.appendingPathComponent("lean/Generated/Program.lean"), encoding: .utf8)
        #expect(try decoder.decodeLeanProgram(lean) == artifact.program)
        let observed = try IRInterpreter(fuel: 64).run(artifact.program, entry: "calculate", arguments: [.bits(try BitPattern(width: 64, bits: 8))])
        #expect(observed.outcome == .returned(.bits(try BitPattern(width: 64, bits: 9))))
        #expect(artifact.metadata.status == "DRAFT_UNVALIDATED")
        #expect(artifact.metadata.schemaVersion == 2)
        await #expect(throws: (any Error).self) { _ = try await artifact.write(to: root) }
        #expect(try Data(contentsOf: root.appendingPathComponent("source.txt")) == bytes)
    }
    @Test(.timeLimit(.minutes(1))) func rejectsIncompleteSourceBeforePublishing() throws {
        for source in [Data([0xff]), Data("actor Store {}".utf8), Data(repeating: 65, count: 1_000_001)] {
            #expect(throws: (any Error).self) { try CompilationArtifactGenerator().generate(CompilationRequest(source: source,language: .swift,moduleID: "Source",evidenceBudget: Self.budget)) }
        }
    }
}
