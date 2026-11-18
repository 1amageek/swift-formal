import Foundation

public actor EvidenceBundleReader: FormalEvidenceReading {
    private struct Cursor {
        let query: FormalGraphQuery
        let selection: Set<String>?
        let frontier: [String]
        let complete: Bool
        let phase: Int
        let offset: Int
    }
    private let database: EvidenceDatabase
    private let budget: EvidenceReadBudget
    private let chunkBytes: Int
    private var cursors: [String: Cursor] = [:]
    private var cursorOrder: [String] = []
    private let cursorNamespace = UUID().uuidString
    private var stopped = false
    public init(root: URL, reference: EvidenceBundleReference, budget: EvidenceReadBudget) throws {
        try EvidenceBudget.validate(budget)
        guard reference.id == reference.sha256, EvidenceIdentity.validID(reference.id), reference.byteCount >= 0, reference.byteCount <= budget.maximumDatabaseBytes else { throw FormalEvidenceError.invalid("Bundle reference") }
        let canonicalRoot = try EvidenceFiles.canonical(root)
        let directory = canonicalRoot.appendingPathComponent(reference.id), file = directory.appendingPathComponent("evidence.sqlite")
        let manifest = directory.appendingPathComponent("manifest.json")
        for url in [directory,file,manifest] {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw FormalEvidenceError.integrity("Symlink bundle") }
        }
        let manifestBytes = try EvidenceFiles.read(manifest,maximum: min(budget.maximumRecordBytes,4096))
        let publication = try JSONDecoder().decode(EvidenceBundleReference.self,from: manifestBytes)
        guard publication == reference else { throw FormalEvidenceError.integrity("Publication manifest/reference mismatch") }
        let actual = try EvidenceFiles.hash(file, maximum: budget.maximumDatabaseBytes)
        guard actual.0 == reference.sha256, actual.1 == reference.byteCount else { throw FormalEvidenceError.integrity("Bundle digest/size") }
        self.budget = budget; database = try EvidenceDatabase(file, writable: false)
        guard try database.scalar("SELECT version FROM metadata") == 1 else { throw FormalEvidenceError.incompatibleVersion }
        chunkBytes = try database.scalar("SELECT chunkBytes FROM metadata")
        guard chunkBytes > 0, chunkBytes <= budget.maximumPageBytes else { throw FormalEvidenceError.limit("Stored chunk size") }
    }
    public func catalog() throws -> EvidenceCatalog {
        try ensureOpen()
        let graphs: [FormalGraphDescriptor] = try rows("graph")
        let documents: [DocumentReference] = try rows("document")
        let traces: [FormalTrace] = try rows("trace")
        let claims: [VerificationClaim] = try rows("claim")
        let result = EvidenceCatalog(schemaVersion: 1, graphs: graphs, documents: documents, traces: traces.map(\.id), claims: claims)
        guard try EvidenceIdentity.encode(result).count <= budget.maximumPageBytes else { throw FormalEvidenceError.limit("Catalog page") }
        return result
    }
    public func graph(_ query: FormalGraphQuery) throws -> FormalGraphPage {
        try ensureOpen()
        guard query.depth >= 0, query.depth <= budget.maximumTraversalNodes,
            ["outgoing","incoming","both"].contains(query.direction), query.roots.count <= min(budget.maximumTraversalNodes, 15_000),
            EvidenceIdentity.validID(query.graphID), query.roots.allSatisfy(EvidenceIdentity.validID),
            query.relations.count <= budget.maximumEdges, query.relations.allSatisfy({ $0.utf8.count <= 256 && !$0.utf8.contains(0) }) else { throw FormalEvidenceError.invalid("Graph query") }
        let descriptor: [FormalGraphDescriptor] = try rows("graph", id: query.graphID)
        guard !descriptor.isEmpty else { throw FormalEvidenceError.missing("Graph") }
        let base = FormalGraphQuery(graphID: query.graphID, roots: query.roots, relations: query.relations, direction: query.direction, depth: query.depth)
        let state: Cursor
        if let token = query.cursor {
            guard let saved = cursors[token], saved.query == base else { throw FormalEvidenceError.invalidCursor }
            touch(token)
            state = saved
        } else { state = try select(base) }
        var offset = state.offset, phase = state.phase, nodes: [FormalNode] = [], edges: [FormalEdge] = [], seen = Set<String>()
        var strings = [query.graphID]
        var condition = "graph=?"
        if let selected = state.selection {
            if selected.isEmpty { return FormalGraphPage(graphID: query.graphID, nodes: [], edges: [], frontier: state.frontier, selectionComplete: state.complete, nextCursor: nil) }
            let values = selected.sorted(); let marks = Array(repeating: "?", count: values.count).joined(separator: ",")
            if query.direction == "outgoing" { condition += " AND source IN (\(marks))"; strings += values }
            else if query.direction == "incoming" { condition += " AND target IN (\(marks))"; strings += values }
            else { condition += " AND (source IN (\(marks)) OR target IN (\(marks)))"; strings += values + values }
        }
        guard strings.count + query.relations.count <= 30_000 else { throw FormalEvidenceError.limit("Selected neighborhood exceeds indexed query capacity; narrow the selection") }
        if !query.relations.isEmpty {
            condition += " AND kind IN (" + Array(repeating: "?", count: query.relations.count).joined(separator: ",") + ")"; strings += query.relations
        }
        if phase == 0 {
            // Every edge carries its endpoints, including cross-page boundaries. Limiting
            // edges to half the node cap guarantees both endpoints fit before byte checks.
            let limit = min(budget.maximumEdges, budget.maximumNodes / 2)
            let batch = try database.records("SELECT payload,digest FROM edges WHERE \(condition) ORDER BY id LIMIT \(limit) OFFSET \(offset)", strings: strings, maximumBytes: budget.maximumPageBytes, as: FormalEdge.self)
            for edge in batch {
                var additions: [FormalNode] = []
                for id in [edge.source,edge.target] where !seen.contains(id) && !additions.contains(where: { $0.id == id }) {
                    let found: [FormalNode] = try rows("node", id: id, parent: query.graphID)
                    guard let node = found.first else { throw FormalEvidenceError.integrity("Dangling endpoint") }
                    additions.append(node)
                }
                let candidate = FormalGraphPage(graphID: query.graphID, nodes: nodes + additions, edges: edges + [edge], frontier: state.frontier, selectionComplete: state.complete, nextCursor: nil)
                guard try EvidenceIdentity.encode(candidate).count <= budget.maximumPageBytes else {
                    guard !edges.isEmpty else { throw FormalEvidenceError.limit("Edge and endpoints cannot fit page") }; break
                }
                nodes += additions; seen.formUnion(additions.map(\.id)); edges.append(edge); offset += 1
            }
            if batch.isEmpty { phase = 1; offset = 0 }
        }
        if phase == 1 {
            let batch: [FormalNode] = try database.records("SELECT payload,digest FROM records WHERE category='node' AND parent=? ORDER BY id LIMIT \(budget.maximumNodes) OFFSET \(offset)", strings: [query.graphID], maximumBytes: budget.maximumPageBytes, as: FormalNode.self)
            for node in batch {
                offset += 1
                if let selection = state.selection, !selection.contains(node.id) { continue }
                let candidate = FormalGraphPage(graphID: query.graphID, nodes: nodes + [node], edges: edges, frontier: state.frontier, selectionComplete: state.complete, nextCursor: nil)
                guard try EvidenceIdentity.encode(candidate).count <= budget.maximumPageBytes else { offset -= 1; guard !nodes.isEmpty else { throw FormalEvidenceError.limit("Node cannot fit page") }; break }
                nodes.append(node)
            }
            if batch.isEmpty { phase = 2 }
        }
        let token: String?
        if phase < 2 {
            let queryBytes = try EvidenceIdentity.encode(base)
            let next = EvidenceIdentity.id("cursor",cursorNamespace,EvidenceIdentity.digest(queryBytes),String(phase),String(offset))
            if cursors[next] == nil, cursors.count >= budget.maximumCursors {
                let oldest = cursorOrder.removeFirst(); cursors.removeValue(forKey: oldest)
            }
            cursors[next] = Cursor(query: base, selection: state.selection, frontier: state.frontier, complete: state.complete, phase: phase, offset: offset)
            touch(next); token = next
        } else { token = nil }
        return FormalGraphPage(graphID: query.graphID, nodes: nodes, edges: edges, frontier: state.frontier, selectionComplete: state.complete, nextCursor: token)
    }
    private func select(_ query: FormalGraphQuery) throws -> Cursor {
        guard !query.roots.isEmpty else { return Cursor(query: query, selection: nil, frontier: [], complete: true, phase: 0, offset: 0) }
        var visited = Set(query.roots), frontier = Set<String>(), pending = query.roots.map { ($0,0) }, index = 0
        while index < pending.count {
            let (id, depth) = pending[index]; index += 1
            let nodes: [FormalNode] = try rows("node", id: id, parent: query.graphID)
            guard !nodes.isEmpty else { throw FormalEvidenceError.missing("Root node") }
            let test = query.direction == "incoming" ? "target=?" : query.direction == "outgoing" ? "source=?" : "(source=? OR target=?)"
            let args = [query.graphID,id] + (query.direction == "both" ? [id] : [])
            let edges = try database.records("SELECT payload,digest FROM edges WHERE graph=? AND \(test) ORDER BY id LIMIT \(budget.maximumTraversalNodes + 1)", strings: args, maximumBytes: budget.maximumPageBytes, as: FormalEdge.self)
            guard edges.count <= budget.maximumTraversalNodes else { throw FormalEvidenceError.limit("Adjacency exceeds traversal budget; narrow the query") }
            for edge in edges where query.relations.isEmpty || query.relations.contains(edge.kind) {
                let other = edge.source == id ? edge.target : edge.source
                if visited.contains(other) { continue }
                if depth == query.depth || visited.count >= budget.maximumTraversalNodes { frontier.insert(other); continue }
                visited.insert(other); pending.append((other,depth + 1))
            }
        }
        guard frontier.count <= budget.maximumTraversalNodes else { throw FormalEvidenceError.limit("Traversal frontier") }
        return Cursor(query: query, selection: visited, frontier: frontier.sorted(), complete: frontier.isEmpty, phase: 0, offset: 0)
    }
    public func trace(_ query: FormalTraceQuery) throws -> FormalTracePage {
        try ensureOpen()
        guard query.start >= 0, query.count > 0, query.count <= budget.maximumNodes else { throw FormalEvidenceError.invalid("Trace window") }
        let values: [FormalTrace] = try rows("trace", id: query.traceID)
        guard let value = values.first, query.start <= value.states.count else { throw FormalEvidenceError.missing("Trace/step") }
        let end = min(value.states.count, query.start + query.count)
        let transitions = query.start < value.transitions.count ? Array(value.transitions[query.start..<min(end,value.transitions.count)]) : []
        return FormalTracePage(traceID: value.id, graphID: value.graphID, start: query.start, states: Array(value.states[query.start..<end]), transitions: transitions, loopBackIndex: value.loopBackIndex, totalSteps: value.states.count, complete: value.complete)
    }
    public func origins(_ query: OriginQuery) throws -> OriginPage {
        try ensureOpen()
        guard query.start >= 0, query.count > 0, query.count <= budget.maximumNodes else { throw FormalEvidenceError.invalid("Origin page") }
        let result: [OriginLink] = try database.records("SELECT payload,digest FROM records WHERE category='origin' AND parent=? ORDER BY id LIMIT \(query.count) OFFSET \(query.start)", strings: [query.documentID], maximumBytes: budget.maximumPageBytes, as: OriginLink.self)
        return OriginPage(origins: result, nextOffset: result.count == query.count ? query.start + result.count : nil)
    }
    public func document(_ query: DocumentRangeQuery) throws -> DocumentChunk {
        try ensureOpen()
        guard query.start >= 0, query.count > 0, query.count <= budget.maximumPageBytes else { throw FormalEvidenceError.invalid("Document range") }
        let values: [DocumentReference] = try rows("document", id: query.documentID)
        guard let value = values.first, query.start <= value.byteCount else { throw FormalEvidenceError.missing("Document/offset") }
        let end = query.start + min(query.count, value.byteCount - query.start)
        var output = Data(), offset = query.start / chunkBytes * chunkBytes
        while offset < end {
            let data = try database.bytes(query.documentID + ":" + String(offset), maximum: chunkBytes)
            let lower = max(query.start,offset) - offset, upper = min(end,offset + data.count) - offset
            guard lower <= upper, upper <= data.count else { throw FormalEvidenceError.integrity("Chunk offset") }
            output.append(data[lower..<upper]); offset += chunkBytes
        }
        guard String(data: output, encoding: .utf8) != nil else { throw FormalEvidenceError.invalid("Range splits UTF-8 code point") }
        return DocumentChunk(document: value, start: query.start, bytes: output, eof: end == value.byteCount)
    }
    public func shutdown() throws { stopped = true; cursors.removeAll(); cursorOrder.removeAll(); try database.close() }
    private func ensureOpen() throws { try Task.checkCancellation(); if stopped { throw FormalEvidenceError.closed } }
    private func touch(_ token: String) {
        cursorOrder.removeAll { $0 == token }; cursorOrder.append(token)
    }
    private func rows<T: Decodable>(_ category: String, id: String? = nil, parent: String? = nil) throws -> [T] {
        try database.records("SELECT payload,digest FROM records WHERE category=?" + (id == nil ? "" : " AND id=?") + (parent == nil ? "" : " AND parent=?") + " ORDER BY id", strings: [category] + (id.map { [$0] } ?? []) + (parent.map { [$0] } ?? []), maximumBytes: budget.maximumPageBytes, as: T.self)
    }
}
