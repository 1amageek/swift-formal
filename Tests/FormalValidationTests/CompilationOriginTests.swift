import Foundation
import Testing
import FormalCompiler
import FormalCore
import FormalIR
import FormalEvidence

@Suite(.timeLimit(.minutes(1)))
struct CompilationOriginTests {
    @Test func partialModelsBindChecksToTheOriginalExpressionAndBothEmittedDefinitions() async throws {
        let source = Data("// λ\nlet rows = dates.count / 7".utf8)
        let bytes = try #require(source.range(of: Data("dates.count / 7".utf8)))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let budget = EvidenceReadBudget(maximumDatabaseBytes: 16_777_216,maximumRecordBytes: 262_144,maximumPageBytes: 1_048_576,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 4096,maximumCursors: 1)
        let bundle = try await SwiftExpressionModels.write(source: source,sites: [.init(bytes: bytes,expression: .arithmetic(.count,.divide,.integer(7)))],to: root,budget: budget)
        let reader = try await LocalFormalEvidenceStore(root: root).open(bundle,budget: budget)
        let catalog = try await reader.catalog()
        #expect(catalog.claims.isEmpty)
        #expect(Set(catalog.graphs.map(\.kind)) == [.leanDeclarations,.tlaSpecification])
        for graph in catalog.graphs {
            #expect(!graph.complete)
            let page = try await reader.graph(.init(graphID: graph.id,roots: graph.roots,relations: [],direction: "outgoing",depth: 3))
            let check = try #require(page.nodes.first { $0.label == "No arithmetic trap" })
            let step = try #require(page.nodes.first { $0.label == "L2 · Collection count / 7" })
            #expect(page.edges.contains { $0.source == step.id && $0.target == check.id && $0.kind == "localCheck" })
            var fragments: [String:String] = [:]
            for span in step.ranges {
                let chunk = try await reader.document(.init(documentID: span.documentID,start: span.start,count: span.end - span.start))
                fragments[chunk.document.language] = String(decoding: chunk.bytes,as: UTF8.self)
            }
            #expect(fragments["swift"] == "dates.count / 7")
            if graph.kind == .leanDeclarations { #expect(fragments["lean"]?.contains("Int.tdiv a (7 : Int)") == true) }
            else { #expect(fragments["tla"]?.contains("Quot(a, 7)") == true) }
        }
        try await reader.shutdown()
    }

    @Test func byteRangesSurviveUnicodeBranchesCallsAndEmission() async throws {
        let source = """
        // α and é retain original byte offsets
        func helper(_ x: Int64) -> Int64 { return x + 1 }
        func choose(_ a: Int64, _ b: Int64) -> Int64 {
            if a < b { return helper(a) } else { return helper(b) }
        }
        """
        let bytes = Data(source.utf8)
        let compilation = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: bytes,language: .swift,moduleID: "Located"))
        let programDigest = EvidenceIdentity.digest(try ArtifactJSON.encode(compilation.program))
        var fragments = Set<String>()
        for origin in compilation.origins {
            let range = try #require(origin.source)
            #expect(range.documentID == compilation.sourceDocument.id)
            #expect(range.start >= 0 && range.end <= bytes.count && range.start <= range.end)
            let fragment = try #require(String(data: bytes.subdata(in: range.start..<range.end),encoding: .utf8))
            fragments.insert(fragment)
            let address = try #require(origin.address)
            #expect(address.programDigest == programDigest)
            let function = try #require(compilation.program.functions.first { $0.symbol == address.function })
            if let ordinal = address.instruction {
                let block = try #require(function.blocks.first { $0.id == address.block })
                #expect(block.instructions.indices.contains(ordinal)); #expect(origin.synthetic)
            }
        }
        #expect(fragments.contains("a < b")); #expect(fragments.contains("helper(a)")); #expect(fragments.contains("helper(b)"))
        let shifted = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data(("// extra α\n" + source).utf8),language: .swift,moduleID: "Located"))
        #expect(shifted.program == compilation.program)
        #expect(shifted.sourceDocument.id != compilation.sourceDocument.id)
        #expect(shifted.origins.first?.source?.start == (compilation.origins.first?.source?.start ?? 0) + "// extra α\n".utf8.count)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let budget = EvidenceReadBudget(maximumDatabaseBytes: 16_777_216,maximumRecordBytes: 262_144,maximumPageBytes: 1_048_576,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 16)
        let artifact = try CompilationArtifactGenerator().generate(CompilationRequest(source: bytes,language: .swift,moduleID: "Located",evidenceBudget: budget))
        for file in artifact.files {
            let output = Data(file.contents.utf8)
            for origin in file.origins {
                let range = try #require(origin.generated)
                #expect(range.documentID == file.reference.id)
                #expect(range.end <= output.count && range.end > range.start)
                #expect(String(data: output.subdata(in: range.start..<range.end),encoding: .utf8) != nil)
            }
        }
        let reference = try await artifact.write(to: root)
        let reader = try await LocalFormalEvidenceStore(root: root.appendingPathComponent("evidence")).open(reference.evidence,budget: budget)
        let origins = try await reader.origins(OriginQuery(documentID: compilation.sourceDocument.id,start: 0,count: 500))
        #expect(origins.origins.contains { $0.generated != nil && $0.source != nil })
        try await reader.shutdown()

        let models = root.appendingPathComponent("models")
        let draft = try await artifact.writeGeneratedModels(to: models)
        let drafts = try await LocalFormalEvidenceStore(root: models).open(draft,budget: budget)
        let catalog = try await drafts.catalog()
        #expect(catalog.claims.isEmpty)
        #expect(Set(catalog.graphs.map(\.kind)) == [.tlaSpecification,.leanDeclarations])
        for graph in catalog.graphs {
            let document = try #require(artifact.files.first { graph.artifactDigests.contains($0.reference.sha256) })
            let page = try await drafts.graph(FormalGraphQuery(graphID: graph.id,roots: graph.roots,relations: [],direction: "outgoing",depth: 32))
            #expect(Set(["then","else","encodes"]).isSubset(of: Set(page.edges.map(\.kind))))
            #expect(page.nodes.contains { $0.label == "choose" })
            #expect(page.nodes.allSatisfy { $0.claimIDs.isEmpty && $0.ranges.first?.documentID == document.reference.id })
            #expect(document.path.hasSuffix(graph.kind == .tlaSpecification ? ".tla" : ".lean"))
        }
        try await drafts.shutdown()
    }
}
