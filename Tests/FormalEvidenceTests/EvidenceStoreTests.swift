import Foundation
import Testing
@testable import FormalEvidence

@Suite(.timeLimit(.minutes(1)))
struct EvidenceStoreTests {
    let budget = EvidenceReadBudget(maximumDatabaseBytes: 8_000_000, maximumRecordBytes: 16_384, maximumPageBytes: 65_536, maximumNodes: 4, maximumEdges: 2, maximumTraversalNodes: 100, maximumCursors: 8)
    @Test func pagesRetainCrossPageEdgesAndUnicode() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Fixture cleanup failed: \(error)") } }
        let writer = try EvidenceBundleWriter(root: root, budget: budget, chunkBytes: 4)
        let graph = EvidenceIdentity.id("graph", "fixture")
        try await writer.graph(FormalGraphDescriptor(id: graph, kind: .leanDeclarations, artifactDigests: [], producer: "test", scope: "fixture", complete: true, extraction: "available", diagnostics: []))
        let nodes = (0..<9).map { FormalNode(id: EvidenceIdentity.id("node", String($0)), kind: "theorem", label: String($0), attributes: [:], ranges: [], claimIDs: []) }
        let edges = (0..<8).map { FormalEdge(id: EvidenceIdentity.id("edge", String($0)), source: nodes[$0].id, target: nodes[$0+1].id, kind: "valueUses", attributes: [:]) }
        for node in nodes { try await writer.append(graphID: graph, nodes: [node], edges: []) }
        for edge in edges { try await writer.append(graphID: graph, nodes: [], edges: [edge]) }
        let bytes = Data("αβ source".utf8), doc = EvidenceIdentity.id("document", "fixture")
        try await writer.document(DocumentReference(id: doc, sha256: EvidenceIdentity.digest(bytes), byteCount: bytes.count, language: "lean", role: "original"), bytes: bytes)
        let reference = try await writer.seal()
        let reader = try await LocalFormalEvidenceStore(root: root).open(reference, budget: budget)
        var cursor: String?, readNodes = Set<String>(), readEdges = Set<String>()
        repeat {
            let page = try await reader.graph(FormalGraphQuery(graphID: graph, roots: [], relations: [], direction: "both", depth: 0, cursor: cursor))
            #expect(page.nodes.count <= 4 && page.edges.count <= 2)
            let endpoints = Set(page.nodes.map(\.id))
            #expect(page.edges.allSatisfy { endpoints.contains($0.source) && endpoints.contains($0.target) })
            readNodes.formUnion(endpoints); readEdges.formUnion(page.edges.map(\.id)); cursor = page.nextCursor
        } while cursor != nil
        #expect(readNodes == Set(nodes.map(\.id))); #expect(readEdges == Set(edges.map(\.id)))
        let chunk = try await reader.document(DocumentRangeQuery(documentID: doc, start: 0, count: 4))
        #expect(String(data: chunk.bytes, encoding: .utf8) == "αβ")
        await #expect(throws: FormalEvidenceError.self) { try await reader.document(DocumentRangeQuery(documentID: doc, start: 1, count: 2)) }
        try await reader.shutdown()
        await #expect(throws: FormalEvidenceError.closed) { try await reader.catalog() }
    }
    @Test func corruptionAndDanglingEdgesFail() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record("Fixture cleanup failed: \(error)") } }
        let writer = try EvidenceBundleWriter(root: root, budget: budget, chunkBytes: 4)
        let graph = EvidenceIdentity.id("graph", "bad")
        try await writer.graph(FormalGraphDescriptor(id: graph, kind: .tlaStateSpace, artifactDigests: [], producer: "test", scope: "finite", complete: false, extraction: "partial", diagnostics: []))
        let missing = EvidenceIdentity.id("node", "missing")
        try await writer.append(graphID: graph, nodes: [], edges: [FormalEdge(id: EvidenceIdentity.id("edge", "bad"), source: missing, target: missing, kind: "transition", attributes: [:])])
        await #expect(throws: FormalEvidenceError.self) { try await writer.seal() }
        try await writer.shutdown()
        let good = try EvidenceBundleWriter(root: root, budget: budget, chunkBytes: 4)
        let reference = try await good.seal()
        let url = root.appendingPathComponent(reference.id).appendingPathComponent("evidence.sqlite")
        let handle = try FileHandle(forWritingTo: url); try handle.seek(toOffset: 100); try handle.write(contentsOf: Data([255])); try handle.close()
        await #expect(throws: FormalEvidenceError.self) { try await LocalFormalEvidenceStore(root: root).open(reference, budget: budget) }
    }
}

extension EvidenceStoreTests {
    @Test func rejectsDanglingAndSplitOriginsBeforeSealing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        for range in [TextRange(documentID: EvidenceIdentity.id("doc","source"), start: 1,end: 2), TextRange(documentID: EvidenceIdentity.id("doc","source"),start: 0,end: 100)] {
            let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: 4)
            let bytes = Data("α source".utf8)
            try await writer.document(DocumentReference(id: range.documentID,sha256: EvidenceIdentity.digest(bytes),byteCount: bytes.count,language: "swift",role: "original"),bytes: bytes)
            try await writer.origin(OriginLink(id: EvidenceIdentity.id("origin",String(range.start)),source: range,address: nil,generated: nil,precision: "expression",producer: "test",synthetic: false))
            await #expect(throws: FormalEvidenceError.self) { try await writer.seal() }
            try await writer.shutdown()
        }
    }
}

extension EvidenceStoreTests {
    @Test func identicalWritesConvergeAndConflictingContentFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: 4)
        let graph = FormalGraphDescriptor(id: EvidenceIdentity.id("graph","immutable"),kind: .leanDeclarations,artifactDigests: [],producer: "test",scope: "immutable",complete: true,extraction: "available",diagnostics: [])
        let node = FormalNode(id: EvidenceIdentity.id("node","immutable"),kind: "theorem",label: "original",attributes: [:],ranges: [],claimIDs: [])
        let edge = FormalEdge(id: EvidenceIdentity.id("edge","immutable"),source: node.id,target: node.id,kind: "uses",attributes: [:])
        let bytes = Data("α text".utf8), doc = DocumentReference(id: EvidenceIdentity.id("doc","immutable"),sha256: EvidenceIdentity.digest(bytes),byteCount: bytes.count,language: "lean",role: "original")
        for _ in 0..<2 {
            try await writer.graph(graph)
            try await writer.append(graphID: graph.id,nodes: [node],edges: [edge])
            try await writer.document(doc,bytes: bytes)
        }
        let conflicting = FormalNode(id: node.id,kind: node.kind,label: "changed",attributes: [:],ranges: [],claimIDs: [])
        await #expect(throws: FormalEvidenceError.self) { try await writer.append(graphID: graph.id,nodes: [conflicting],edges: []) }
        let reference = try await writer.seal()
        let reader = try await LocalFormalEvidenceStore(root: root).open(reference,budget: budget)
        let page = try await reader.graph(FormalGraphQuery(graphID: graph.id,roots: [],relations: [],direction: "both",depth: 0))
        #expect(page.nodes == [node] && page.edges == [edge])
        try await reader.shutdown()
    }
    @Test func cursorReplayPreservesPageAndRejectsDifferentQuery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: 4)
        let graph = EvidenceIdentity.id("graph","cursor")
        try await writer.graph(FormalGraphDescriptor(id: graph,kind: .leanDeclarations,artifactDigests: [],producer: "test",scope: "cursor",complete: true,extraction: "available",diagnostics: []))
        for index in 0..<12 {
            try await writer.append(graphID: graph,nodes: [FormalNode(id: EvidenceIdentity.id("cursor-node",String(index)),kind: "theorem",label: String(index),attributes: [:],ranges: [],claimIDs: [])],edges: [])
        }
        let reference = try await writer.seal()
        let reader = try await LocalFormalEvidenceStore(root: root).open(reference,budget: budget)
        let first = try await reader.graph(FormalGraphQuery(graphID: graph,roots: [],relations: [],direction: "both",depth: 0))
        let cursor = try #require(first.nextCursor)
        let query = FormalGraphQuery(graphID: graph,roots: [],relations: [],direction: "both",depth: 0,cursor: cursor)
        let second = try await reader.graph(query)
        let repeated = try await reader.graph(query)
        #expect(second == repeated)
        await #expect(throws: FormalEvidenceError.invalidCursor) { try await reader.graph(FormalGraphQuery(graphID: graph,roots: [],relations: ["changed"],direction: "both",depth: 0,cursor: cursor)) }
        try await reader.shutdown()
    }
}

extension EvidenceStoreTests {
    @Test func discardOptionalGraphPreservesOtherGraphsAndSealsWithoutDanglingEdges() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: 4)
        let keep = EvidenceIdentity.id("graph","keep"), discard = EvidenceIdentity.id("graph","discard")
        let node = FormalNode(id: EvidenceIdentity.id("node","keep"),kind: "theorem",label: "kept",attributes: [:],ranges: [],claimIDs: [])
        for graph in [keep,discard] { try await writer.graph(FormalGraphDescriptor(id: graph,kind: .leanDeclarations,artifactDigests: [],producer: "test",scope: "fixture",complete: false,extraction: "partial",diagnostics: [])) }
        try await writer.append(graphID: keep,nodes: [node],edges: [])
        let missing = EvidenceIdentity.id("node","missing")
        try await writer.append(graphID: discard,nodes: [],edges: [FormalEdge(id: EvidenceIdentity.id("edge","discard"),source: missing,target: missing,kind: "uses",attributes: [:])])
        try await writer.discardGraph(discard)
        let reference = try await writer.seal()
        let reader = try await LocalFormalEvidenceStore(root: root).open(reference,budget: budget)
        let catalog = try await reader.catalog()
        #expect(catalog.graphs.map(\.id) == [keep])
        let page = try await reader.graph(FormalGraphQuery(graphID: keep,roots: [],relations: [],direction: "both",depth: 0))
        #expect(page.nodes == [node])
        try await reader.shutdown()
    }
}

extension EvidenceStoreTests {
    @Test func rootsAreRetainedAndMissingOrDuplicateRootReferencesRejectSealing() async throws {
        for invalid in [false,true] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: 4)
            let graph = EvidenceIdentity.id("graph","roots"), node = EvidenceIdentity.id("node","root")
            let declared = invalid ? EvidenceIdentity.id("node","missing-root") : node
            let descriptor = FormalGraphDescriptor(id: graph,kind: .leanDeclarations,roots: [declared],artifactDigests: [],producer: "test",scope: "Root reference fixture",complete: true,extraction: "available",diagnostics: [])
            try await writer.graph(descriptor)
            try await writer.append(graphID: graph,nodes: [FormalNode(id: node,kind: "theorem",label: "Root",attributes: [:],ranges: [],claimIDs: [])],edges: [])
            if invalid {
                await #expect(throws: FormalEvidenceError.self) { try await writer.seal() }
                try await writer.shutdown()
            } else {
                let reference = try await writer.seal()
                let reader = try await LocalFormalEvidenceStore(root: root).open(reference,budget: budget)
                #expect(try await reader.catalog().graphs.first?.roots == [node])
                try await reader.shutdown()
            }
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: 4)
        let graph = EvidenceIdentity.id("graph","duplicate-roots"), node = EvidenceIdentity.id("node","root")
        try await writer.graph(FormalGraphDescriptor(id: graph,kind: .tlaStateSpace,roots: [node,node],artifactDigests: [],producer: "test",scope: "Duplicate roots",complete: false,extraction: "available",diagnostics: []))
        try await writer.append(graphID: graph,nodes: [FormalNode(id: node,kind: "state",label: "Initial",attributes: [:],ranges: [],claimIDs: [])],edges: [])
        await #expect(throws: FormalEvidenceError.self) { try await writer.seal() }
        try await writer.shutdown()
    }
}
