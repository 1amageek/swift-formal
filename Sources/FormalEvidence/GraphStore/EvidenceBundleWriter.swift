import Foundation

public actor EvidenceBundleWriter {
    private let root: URL
    private let staging: URL
    private let database: EvidenceDatabase
    private let budget: EvidenceReadBudget
    private let chunkBytes: Int
    private var terminal = false
    public init(root: URL, budget: EvidenceReadBudget, chunkBytes: Int) throws {
        try EvidenceBudget.validate(budget)
        guard chunkBytes > 0, chunkBytes <= budget.maximumPageBytes else { throw FormalEvidenceError.invalid("Chunk budget") }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        self.root = try EvidenceFiles.canonical(root); self.budget = budget; self.chunkBytes = chunkBytes
        staging = self.root.appendingPathComponent(".staging-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var opened: EvidenceDatabase?
        do {
            let connection = try EvidenceDatabase(staging.appendingPathComponent("evidence.sqlite"), writable: true)
            opened = connection
            try connection.execute("CREATE TABLE records(category TEXT NOT NULL,id TEXT NOT NULL,parent TEXT NOT NULL,payload BLOB NOT NULL,digest TEXT NOT NULL,PRIMARY KEY(category,id))")
            try connection.execute("CREATE INDEX record_parent ON records(category,parent,id)")
            try connection.execute("CREATE TABLE edges(id TEXT PRIMARY KEY,graph TEXT NOT NULL,source TEXT NOT NULL,target TEXT NOT NULL,kind TEXT NOT NULL,payload BLOB NOT NULL,digest TEXT NOT NULL)")
            try connection.execute("CREATE INDEX edge_source ON edges(graph,source,id)")
            try connection.execute("CREATE INDEX edge_target ON edges(graph,target,id)")
            try connection.execute("CREATE TABLE chunks(id TEXT PRIMARY KEY,payload BLOB NOT NULL,digest TEXT NOT NULL)")
            try connection.execute("CREATE TABLE metadata(version INTEGER NOT NULL,chunkBytes INTEGER NOT NULL)")
            try connection.execute("INSERT INTO metadata VALUES(1,\(chunkBytes))")
            database = connection
        } catch {
            do { try opened?.close(); try FileManager.default.removeItem(at: staging) }
            catch let cleanup { throw FormalEvidenceError.io("Writer initialization failed (\(error)); cleanup failed (\(cleanup))") }
            throw error
        }
    }
    public func graph(_ descriptor: FormalGraphDescriptor) throws { try singleRecord("graph", id: descriptor.id, parent: "", value: descriptor) }
    public func append(graphID: String, nodes: [FormalNode], edges: [FormalEdge]) throws {
        try ensureOpen()
        guard nodes.count <= budget.maximumNodes, edges.count <= budget.maximumEdges else { throw FormalEvidenceError.limit("Append batch size") }
        try database.execute("BEGIN IMMEDIATE")
        do {
            for node in nodes { try record("node", id: node.id, parent: graphID, value: node) }
            for edge in edges {
                guard EvidenceIdentity.validID(edge.id), EvidenceIdentity.validID(edge.source), EvidenceIdentity.validID(edge.target) else { throw FormalEvidenceError.invalid("Edge identity") }
                let bytes = try encode(edge)
                let exists = try database.scalar("SELECT count(*) FROM edges WHERE id=?",strings: [edge.id])
                if exists != 0 {
                    let matches = try database.scalar("SELECT count(*) FROM edges WHERE id=? AND graph=? AND source=? AND target=? AND kind=? AND digest=?",strings: [edge.id,graphID,edge.source,edge.target,edge.kind,EvidenceIdentity.digest(bytes)])
                    guard matches == 1 else { throw FormalEvidenceError.integrity("Immutable edge conflict") }
                    continue
                }
                try database.execute("INSERT INTO edges(id,graph,source,target,kind,digest,payload) VALUES(?,?,?,?,?,?,?)", strings: [edge.id,graphID,edge.source,edge.target,edge.kind,EvidenceIdentity.digest(bytes)], blob: bytes)
            }
            try checkSize(); try database.execute("COMMIT")
        } catch { try database.execute("ROLLBACK"); throw error }
    }
    public func document(_ document: DocumentReference, bytes: Data) throws {
        try ensureOpen()
        guard document.byteCount == bytes.count, document.sha256 == EvidenceIdentity.digest(bytes), String(data: bytes, encoding: .utf8) != nil else { throw FormalEvidenceError.integrity("Document bytes") }
        try database.execute("BEGIN IMMEDIATE")
        do {
            try record("document", id: document.id, parent: "", value: document)
            var offset = 0
            while offset < bytes.count {
                let end = min(bytes.count, offset + chunkBytes), chunk = bytes.subdata(in: offset..<end)
                let key = document.id + ":" + String(offset)
                let exists = try database.scalar("SELECT count(*) FROM chunks WHERE id=?",strings: [key])
                if exists != 0 {
                    let existing = try database.bytes(key,maximum: chunkBytes)
                    guard existing == chunk else { throw FormalEvidenceError.integrity("Immutable chunk conflict") }
                } else {
                    try database.execute("INSERT INTO chunks(id,digest,payload) VALUES(?,?,?)", strings: [key, EvidenceIdentity.digest(chunk)], blob: chunk)
                }
                offset = end
            }
            try checkSize(); try database.execute("COMMIT")
        } catch { try database.execute("ROLLBACK"); throw error }
    }
    public func origin(_ value: OriginLink) throws { try singleRecord("origin", id: value.id, parent: value.source?.documentID ?? "", value: value) }
    public func trace(_ value: FormalTrace) throws {
        guard value.states.count <= budget.maximumTraversalNodes, value.transitions.count <= value.states.count,
            value.loopBackIndex.map({ $0 >= 0 && $0 < value.states.count }) ?? true else { throw FormalEvidenceError.invalid("Trace bounds") }
        try singleRecord("trace", id: value.id, parent: value.graphID, value: value)
    }
    public func claim(_ value: VerificationClaim) throws { try singleRecord("claim", id: value.id, parent: "", value: value) }
    public func discardGraph(_ graphID: String) throws {
        try ensureOpen()
        guard EvidenceIdentity.validID(graphID) else { throw FormalEvidenceError.invalid("Graph identity") }
        try database.execute("BEGIN IMMEDIATE")
        do {
            try database.execute("DELETE FROM edges WHERE graph=?",strings: [graphID])
            try database.execute("DELETE FROM records WHERE (category='node' OR category='trace') AND parent=?",strings: [graphID])
            try database.execute("DELETE FROM records WHERE category='graph' AND id=?",strings: [graphID])
            try database.execute("COMMIT")
        } catch { try database.execute("ROLLBACK"); throw error }
    }
    public func seal() throws -> EvidenceBundleReference {
        try ensureOpen()
        let dangling = try database.scalar("SELECT count(*) FROM edges e WHERE NOT EXISTS(SELECT 1 FROM records n WHERE n.category='node' AND n.parent=e.graph AND n.id=e.source) OR NOT EXISTS(SELECT 1 FROM records n WHERE n.category='node' AND n.parent=e.graph AND n.id=e.target)")
        guard dangling == 0 else { throw FormalEvidenceError.integrity("Dangling graph endpoints") }
        let orphan = try database.scalar("SELECT count(*) FROM records n WHERE n.category='node' AND NOT EXISTS(SELECT 1 FROM records g WHERE g.category='graph' AND g.id=n.parent)")
        guard orphan == 0 else { throw FormalEvidenceError.integrity("Unknown graph") }
        try auditReferences()
        try checkSize(); try database.close(); terminal = true
        let path = staging.appendingPathComponent("evidence.sqlite")
        let (digest, count) = try EvidenceFiles.hash(path, maximum: budget.maximumDatabaseBytes)
        let reference = EvidenceBundleReference(id: digest, sha256: digest, byteCount: count)
        try EvidenceIdentity.encode(reference).write(to: staging.appendingPathComponent("manifest.json"))
        try EvidenceFiles.sync(path); try EvidenceFiles.sync(staging.appendingPathComponent("manifest.json")); try EvidenceFiles.sync(staging)
        let destination = root.appendingPathComponent(digest)
        if FileManager.default.fileExists(atPath: destination.path) {
            let existing = try EvidenceFiles.hash(destination.appendingPathComponent("evidence.sqlite"), maximum: budget.maximumDatabaseBytes)
            guard existing.0 == digest else { throw FormalEvidenceError.integrity("Immutable bundle conflict") }
            try FileManager.default.removeItem(at: staging)
        } else { try FileManager.default.moveItem(at: staging, to: destination) }
        try EvidenceFiles.sync(root)
        return reference
    }
    public func shutdown() throws {
        if !terminal { try database.close(); terminal = true }
        if FileManager.default.fileExists(atPath: staging.path) { try FileManager.default.removeItem(at: staging) }
    }
    private func singleRecord<T: Encodable>(_ category: String,id: String,parent: String,value: T) throws {
        try ensureOpen(); try database.execute("BEGIN IMMEDIATE")
        do { try record(category,id: id,parent: parent,value: value); try database.execute("COMMIT") }
        catch { try database.execute("ROLLBACK"); throw error }
    }
    private func record<T: Encodable>(_ category: String, id: String, parent: String, value: T) throws {
        try ensureOpen(); guard EvidenceIdentity.validID(id) else { throw FormalEvidenceError.invalid("Record identity") }
        let bytes = try encode(value)
        let exists = try database.scalar("SELECT count(*) FROM records WHERE category=? AND id=?",strings: [category,id])
        if exists != 0 {
            let matches = try database.scalar("SELECT count(*) FROM records WHERE category=? AND id=? AND parent=? AND digest=?",strings: [category,id,parent,EvidenceIdentity.digest(bytes)])
            guard matches == 1 else { throw FormalEvidenceError.integrity("Immutable record conflict") }
            return
        }
        try database.execute("INSERT INTO records(category,id,parent,digest,payload) VALUES(?,?,?,?,?)", strings: [category,id,parent,EvidenceIdentity.digest(bytes)], blob: bytes)
        try checkSize()
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let bytes = try EvidenceIdentity.encode(value)
        guard bytes.count <= budget.maximumRecordBytes else { throw FormalEvidenceError.limit("Record bytes") }
        return bytes
    }
    private func checkSize() throws {
        let pages = try database.scalar("PRAGMA page_count"), size = try database.scalar("PRAGMA page_size")
        guard size > 0, pages <= budget.maximumDatabaseBytes / size else { throw FormalEvidenceError.limit("Database storage") }
    }
    private func auditReferences() throws {
        try audit("graph",as: FormalGraphDescriptor.self,key: { $0.id }) { graph in
            guard Set(graph.roots).count == graph.roots.count, graph.roots.allSatisfy(EvidenceIdentity.validID) else { throw FormalEvidenceError.integrity("Graph root identities") }
            for id in graph.roots {
                let exists = try database.scalar("SELECT count(*) FROM records WHERE category='node' AND parent=? AND id=?",strings: [graph.id,id])
                guard exists == 1 else { throw FormalEvidenceError.integrity("Graph root does not belong to its graph") }
            }
        }
        try audit("origin", as: OriginLink.self, key: { $0.id }) { value in
            for range in [value.source,value.generated].compactMap({ $0 }) { try validate(range) }
            if let address = value.address {
                guard EvidenceIdentity.validID(address.programDigest), !address.function.isEmpty, address.instruction.map({ $0 >= 0 && address.block != nil }) ?? true else { throw FormalEvidenceError.integrity("Invalid IR address") }
            }
            guard value.source != nil || value.precision == "unavailable" || value.precision == "generatedSegment" else { throw FormalEvidenceError.integrity("Missing precise source origin") }
        }
        try audit("node", as: FormalNode.self, key: { $0.id }) { value in
            for range in value.ranges { try validate(range) }
            for id in value.claimIDs {
                let claims: [VerificationClaim] = try database.records("SELECT payload,digest FROM records WHERE category='claim' AND id=?",strings: [id],maximumBytes: budget.maximumRecordBytes,as: VerificationClaim.self)
                guard !claims.isEmpty else { throw FormalEvidenceError.integrity("Dangling node claim") }
            }
        }
        try audit("trace", as: FormalTrace.self, key: { $0.id }) { trace in
            for id in trace.states {
                let nodes: [FormalNode] = try database.records("SELECT payload,digest FROM records WHERE category='node' AND parent=? AND id=?",strings: [trace.graphID,id],maximumBytes: budget.maximumRecordBytes,as: FormalNode.self)
                guard !nodes.isEmpty else { throw FormalEvidenceError.integrity("Dangling trace state") }
            }
            for id in trace.transitions {
                let edges: [FormalEdge] = try database.records("SELECT payload,digest FROM edges WHERE graph=? AND id=?",strings: [trace.graphID,id],maximumBytes: budget.maximumRecordBytes,as: FormalEdge.self)
                guard !edges.isEmpty else { throw FormalEvidenceError.integrity("Dangling trace transition") }
            }
        }
    }
    private func audit<T: Decodable>(_ category: String, as: T.Type, key: (T) -> String, check: (T) throws -> Void) throws {
        var previous = ""
        while true {
            try Task.checkCancellation()
            let values = try database.records("SELECT payload,digest FROM records WHERE category=? AND id>? ORDER BY id LIMIT 1",strings: [category,previous],maximumBytes: budget.maximumRecordBytes,as: T.self)
            guard let value = values.first else { return }
            try check(value); let next = key(value)
            guard next > previous else { throw FormalEvidenceError.integrity("Record key differs from payload") }; previous = next
        }
    }
    private func validate(_ range: TextRange) throws {
        let documents: [DocumentReference] = try database.records("SELECT payload,digest FROM records WHERE category='document' AND id=?",strings: [range.documentID],maximumBytes: budget.maximumRecordBytes,as: DocumentReference.self)
        guard let document = documents.first, range.start >= 0, range.end >= range.start, range.end <= document.byteCount else { throw FormalEvidenceError.integrity("Origin range/document mismatch") }
        for offset in [range.start,range.end] where offset < document.byteCount {
            let base = offset / chunkBytes * chunkBytes
            let bytes = try database.bytes(range.documentID + ":" + String(base),maximum: chunkBytes)
            guard offset - base < bytes.count, bytes[offset-base] & 0xc0 != 0x80 else { throw FormalEvidenceError.integrity("Origin splits UTF-8 code point") }
        }
    }
    private func ensureOpen() throws { if terminal { throw FormalEvidenceError.closed } }
}
