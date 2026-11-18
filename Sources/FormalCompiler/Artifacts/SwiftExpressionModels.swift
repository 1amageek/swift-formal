import Foundation
import FormalCore
import FormalEvidence

public enum SwiftExpressionModels {
    public static let producer = "swift-formal/swift-expression-v1"

    public static func write(source: Data, sites: [SwiftExpressionSite], to root: URL, budget: EvidenceReadBudget) async throws -> EvidenceBundleReference {
        guard !sites.isEmpty else { throw FormalDiagnostic(.unsupportedOperation, "No supported Swift computations or branches in this selection") }
        guard source.count <= 1_000_000, budget.maximumNodes > 0, sites.count <= (budget.maximumNodes - 1) / 4,
              sites.allSatisfy({ !$0.bytes.isEmpty && $0.bytes.lowerBound >= 0 && $0.bytes.upperBound <= source.count })
        else { throw FormalEvidenceError.limit("Expression model exceeds source, range or graph bounds") }
        let digest = EvidenceIdentity.digest(source)
        let original = DocumentReference(id: EvidenceIdentity.id("source-document", digest, "swift"), sha256: digest, byteCount: source.count, language: "swift", role: "original")
        let writer = try EvidenceBundleWriter(root: root, budget: budget, chunkBytes: budget.maximumRecordBytes)
        do {
            try await writer.document(original, bytes: source)
            let lines = source.indices.filter { source[$0] == 10 }
            for lean in [false, true] {
                let path = lean ? "Expressions.lean" : "Expressions.tla"
                var contents = lean ? "" : "---- MODULE Expressions ----\nEXTENDS Integers\nAbsInt(x) == IF x < 0 THEN -x ELSE x\nQuot(x,y) == IF (x < 0) = (y < 0) THEN AbsInt(x) \\div AbsInt(y) ELSE -(AbsInt(x) \\div AbsInt(y))\n"
                var spans: [Range<Int>] = []
                for (index, site) in sites.enumerated() {
                    try Task.checkCancellation()
                    let start = contents.utf8.count
                    contents += site.definition("Site" + String(index + 1), lean: lean)
                    spans.append(start..<contents.utf8.count)
                }
                if !lean { contents += "====\n" }
                let doc = GeneratedDocument(path: path, contents: contents, origins: []).reference
                try await writer.document(doc, bytes: Data(contents.utf8))
                let graph = EvidenceIdentity.id("expression-graph", original.id, doc.id, sites.map { "\($0.bytes.lowerBound)-\($0.bytes.upperBound)" }.joined(separator: ","))
                let rootID = EvidenceIdentity.id("expression-root",graph)
                var nodes = [FormalNode(id: rootID, kind: "module", label: path, attributes: [:], ranges: [], claimIDs: [])]
                var edges: [FormalEdge] = []
                func connect(_ from: String, _ to: String, _ kind: String) {
                    edges.append(FormalEdge(id: EvidenceIdentity.id("expression-edge",from,to,kind),source: from,target: to,kind: kind,attributes: [:]))
                }
                for (index, site) in sites.enumerated() {
                    let id = EvidenceIdentity.id("expression-site",graph,String(index))
                    let line = lines.partitioningIndex(before: site.bytes.lowerBound) + 1
                    let span = spans[index]
                    let ranges: [FormalEvidence.TextRange] = [.init(documentID: doc.id,start: span.lowerBound,end: span.upperBound),
                        .init(documentID: original.id,start: site.bytes.lowerBound,end: site.bytes.upperBound)]
                    var children: [(String,String)] = []
                    let title: String
                    switch site.expression {
                    case .arithmetic(let lhs, let op, let rhs):
                        title = lhs.label + " " + op.rawValue + " " + rhs.label
                        children = [("localCheck", site.localCheck)]
                    case .conditional(let isGuard, let predicate):
                        title = isGuard ? "Guard condition" : "If condition"
                        children = [("true",isGuard ? "Continue" : "Then branch"),("false",isGuard ? "Guard failure" : "Else path")]
                        if case .opaque = predicate { children.append(("input","Predicate abstracted")) }
                    }
                    nodes.append(FormalNode(id: id,kind: "action",label: "L\(line) · " + title,attributes: [:],ranges: ranges,claimIDs: []))
                    connect(rootID,id,"models")
                    for (role,label) in children {
                        let child = EvidenceIdentity.id("expression-fact",id,role)
                        nodes.append(FormalNode(id: child,kind: "block",label: label,attributes: [:],ranges: ranges,claimIDs: []))
                        connect(id,child,role)
                    }
                }
                try await writer.graph(FormalGraphDescriptor(id: graph,kind: lean ? .leanDeclarations : .tlaSpecification,roots: [rootID],
                    artifactDigests: [doc.sha256,original.sha256],producer: producer,scope: "Independent integer expressions and abstract branch predicates",complete: false,extraction: "available",diagnostics: []))
                try await writer.append(graphID: graph,nodes: nodes,edges: edges)
            }
            return try await writer.seal()
        } catch { try await writer.shutdown(); throw error }
    }
}

private extension Array where Element == Int {
    func partitioningIndex(before offset: Int) -> Int {
        var low = 0, high = count
        while low < high {
            let mid = low + (high - low) / 2
            if self[mid] < offset { low = mid + 1 } else { high = mid }
        }
        return low
    }
}
