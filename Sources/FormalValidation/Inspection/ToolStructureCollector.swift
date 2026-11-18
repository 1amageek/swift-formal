import Foundation
import FormalCore
import FormalEvidence

struct ToolStructureCollector {
    struct SANYRecord: Decodable {
        let record: String
        let id: String?
        let kind: String?
        let label: String?
        let module: String?
        let source: String?
        let target: String?
        let beginLine: Int?
        let root: String?
        let beginColumn: Int?
        let endLine: Int?
        let endColumn: Int?
    }
    struct LeanOutput: Decodable {
        struct Declaration: Decodable { let name: String; let kind: String; let typeUses: [String]; let valueUses: [String]; let bodyAvailable: Bool }
        struct Term: Decodable { let id: String; let kind: String; let label: String; let children: [String] }
        let schemaVersion: Int
        let root: String
        let kernelReplayed: Bool
        let axioms: [String]
        let records: [Declaration]
        let terms: [Term]
    }
    static func tla(_ output: String,context: String,module: String,documents: [String: (DocumentReference, Data)]) throws -> (FormalGraphDescriptor,[FormalNode],[FormalEdge]) {
        let graph = EvidenceIdentity.id("sany-graph",context,module)
        var nodes: [FormalNode] = [], edges: [FormalEdge] = []; var complete = false; var rootID: String?
        for line in output.split(separator: "\n") {
            let record = try JSONDecoder().decode(SANYRecord.self,from: Data(line.utf8))
            switch record.record {
            case "node":
                guard let key = record.id, let kind = record.kind, let label = record.label else { throw FormalEvidenceError.integrity("SANY node") }
                var ranges: [FormalEvidence.TextRange] = []
                if let name = record.module, let document = documents[name + ".tla"], let range = range(record,document: document.0,bytes: document.1) { ranges = [range] }
                nodes.append(FormalNode(id: EvidenceIdentity.id("sany-node",graph,key),kind: kind,label: label,attributes: ["module":record.module ?? "unavailable","origin":"SANY semantic graph"],ranges: ranges,claimIDs: []))
            case "edge":
                guard let source = record.source, let target = record.target, let kind = record.kind else { throw FormalEvidenceError.integrity("SANY edge") }
                edges.append(FormalEdge(id: EvidenceIdentity.id("sany-edge",graph,source,target,kind),source: EvidenceIdentity.id("sany-node",graph,source),target: EvidenceIdentity.id("sany-node",graph,target),kind: kind,attributes: [:]))
            case "complete":
                guard !complete, let root = record.root, record.module == module else { throw FormalEvidenceError.integrity("Missing/duplicate SANY root completion") }
                rootID = EvidenceIdentity.id("sany-node",graph,root); complete = true
            default: throw FormalEvidenceError.integrity("Unknown SANY record")
            }
        }
        guard complete, let rootID, nodes.contains(where: { $0.id == rootID }), !nodes.isEmpty, Set(nodes.map(\.id)).count == nodes.count else { throw FormalEvidenceError.integrity("Incomplete SANY collector") }
        return (FormalGraphDescriptor(id: graph,kind: .tlaSpecification,roots: [rootID],artifactDigests: Set(documents.values.map { $0.0.sha256 }).sorted(),producer: "SANY/tla2tools-1.7.4",scope: "Analyzed module and recorded imports",complete: true,extraction: "available",diagnostics: []),nodes,Array(Dictionary(grouping: edges,by: \.id).values.compactMap(\.first)))
    }
    static func lean(_ output: String,context: String,module: String,root: String,artifacts: [String],allowedAxioms: [String]) throws -> (FormalGraphDescriptor,[FormalNode],[FormalEdge],FormalGraphDescriptor,[FormalNode],[FormalEdge],LeanOutput) {
        let lines = output.split(separator: "\n").filter { $0.hasPrefix("FORMAL_GRAPH_JSON ") }
        guard lines.count == 1, let line = lines.first else { throw FormalEvidenceError.integrity("Missing trusted Lean collector result") }
        let result = try JSONDecoder().decode(LeanOutput.self,from: Data(line.dropFirst("FORMAL_GRAPH_JSON ".count).utf8))
        guard result.schemaVersion == 1, result.kernelReplayed, result.root == root,
            !result.axioms.contains(where: { $0.lowercased().contains("sorry") }), Set(result.axioms).isSubset(of: Set(allowedAxioms)) else { throw FormalEvidenceError.integrity("Lean kernel/axiom audit rejected") }
        let graph = EvidenceIdentity.id("lean-declarations",context,module,root)
        func id(_ name: String) -> String { EvidenceIdentity.id("lean-node",graph,name) }
        let nodes = result.records.map { FormalNode(id: id($0.name),kind: $0.kind,label: $0.name,attributes: ["bodyAvailable":String($0.bodyAvailable),"moduleContext":module,"kernelReplayed":"true"],ranges: [],claimIDs: []) }
        var edges: [FormalEdge] = []
        for record in result.records {
            for (kind,uses) in [("typeUses",record.typeUses),("valueUses",record.valueUses)] {
                for target in uses { edges.append(FormalEdge(id: EvidenceIdentity.id("lean-edge",graph,record.name,target,kind),source: id(record.name),target: id(target),kind: kind,attributes: [:])) }
            }
        }
        for axiom in result.axioms { edges.append(FormalEdge(id: EvidenceIdentity.id("lean-axiom",graph,root,axiom),source: id(root),target: id(axiom),kind: "usesAxiom",attributes: ["transitive":"true"])) }
        guard result.records.contains(where: { $0.name == root }) else { throw FormalEvidenceError.integrity("Lean replayed root declaration is missing") }
        let descriptor = FormalGraphDescriptor(id: graph,kind: .leanDeclarations,roots: [id(root)],artifactDigests: artifacts,producer: "Lean/4.35.0/kernel-replay",scope: "Actual reachable type/value declarations; unavailable bodies remain explicit",complete: true,extraction: "available",diagnostics: [])
        let termGraph = EvidenceIdentity.id("lean-proof-term",context,module,root)
        func termID(_ key: String) -> String { EvidenceIdentity.id("lean-term",termGraph,key) }
        let terms = result.terms.map { FormalNode(id: termID($0.id),kind: $0.kind,label: $0.label,attributes: ["path":$0.id],ranges: [],claimIDs: []) }
        let termEdges = result.terms.flatMap { record in record.children.map { target in FormalEdge(id: EvidenceIdentity.id("lean-term-edge",termGraph,record.id,target),source: termID(record.id),target: termID(target),kind: "expressionChild",attributes: [:]) } }
        guard terms.isEmpty || result.terms.contains(where: { $0.id == "0" }) else { throw FormalEvidenceError.integrity("Lean expression root is missing") }
        let termDescriptor = FormalGraphDescriptor(id: termGraph,kind: .leanProofTerm,roots: terms.isEmpty ? [] : [termID("0")],artifactDigests: artifacts,producer: "Lean/4.35.0/kernel-replay",scope: "Actual checked expression tree; no tactic timeline",complete: !terms.isEmpty,extraction: terms.isEmpty ? "unavailable" : "available",diagnostics: terms.isEmpty ? ["Opaque or unavailable declaration body"] : [])
        return (descriptor,nodes,edges,termDescriptor,terms,termEdges,result)
    }
    private static func range(_ record: SANYRecord,document: DocumentReference,bytes: Data) -> FormalEvidence.TextRange? {
        guard let line = record.beginLine, let column = record.beginColumn, let endLine = record.endLine, let endColumn = record.endColumn,
            line > 0, column > 0, endLine >= line, endColumn > 0 else { return nil }
        let lines = bytes.split(separator: 10,omittingEmptySubsequences: false)
        guard endLine <= lines.count else { return nil }
        // The pinned generated profile is ASCII. Tabs/non-ASCII columns are not
        // guessed from Java character coordinates; missing precision is explicit.
        guard lines[line-1].allSatisfy({ $0 < 128 && $0 != 9 }), lines[endLine-1].allSatisfy({ $0 < 128 && $0 != 9 }), column <= lines[line-1].count + 1, endColumn <= lines[endLine-1].count else { return nil }
        let start = lines[..<(line-1)].reduce(0) { $0 + $1.count + 1 } + column - 1
        let end = lines[..<(endLine-1)].reduce(0) { $0 + $1.count + 1 } + endColumn
        return FormalEvidence.TextRange(documentID: document.id,start: start,end: end)
    }
}
