import Foundation
import FormalCore
import FormalEvidence
import FormalIR

extension CompilationArtifact {
    /// Seals the emitted program documents and their encoded control flow without running a verifier.
    public func writeGeneratedModels(to root: URL) async throws -> EvidenceBundleReference {
        let writer = try EvidenceBundleWriter(root: root,budget: budget,chunkBytes: budget.maximumRecordBytes)
        let bundle: EvidenceBundleReference
        do {
            var kinds = Set<String>()
            for document in files {
                try Task.checkCancellation()
                let reference = document.reference
                try await writer.document(reference,bytes: Data(document.contents.utf8))
                guard !document.origins.isEmpty else { continue }
                try await Self.graph(document,reference: reference,artifact: self,writer: writer,budget: budget)
                kinds.insert(reference.language)
            }
            guard kinds == ["tla","lean"] else { throw FormalDiagnostic(.integrityMismatch,"Both generated programs need emitter ranges") }
            bundle = try await writer.seal()
        } catch {
            try await writer.shutdown()
            throw error
        }
        return bundle
    }

    private static func graph(_ doc: GeneratedDocument,reference: DocumentReference,artifact: CompilationArtifact,writer: EvidenceBundleWriter,budget: EvidenceReadBudget) async throws {
        let graph = EvidenceIdentity.id("emitted-program",reference.id)
        var nodes: [FormalNode] = [], edges: [FormalEdge] = [], roots: [String] = []
        var ranges: [IRAddress:FormalEvidence.TextRange] = [:]
        for origin in doc.origins {
            if let address = origin.address, let range = origin.generated { ranges[address] = range }
        }
        guard let digest = doc.origins.first?.address?.programDigest else { throw FormalDiagnostic(.integrityMismatch,"No emitted program") }
        func id(_ f: String,_ b: String = "",_ part: String = "") -> String { EvidenceIdentity.id("emitted-node",graph,f,b,part) }
        func node(_ id: String,_ kind: String,_ name: String,_ address: IRAddress) throws {
            guard nodes.count < budget.maximumNodes else { throw FormalEvidenceError.limit("Generated model nodes exceed graph capacity") }
            guard let range = ranges[address], range.documentID == reference.id else {
                throw FormalDiagnostic(.integrityMismatch,"Missing program emitter range")
            }
            nodes.append(FormalNode(id: id,kind: kind,label: name,attributes: [:],ranges: [range],claimIDs: []))
        }
        func edge(_ from: String,_ to: String,_ kind: String) {
            edges.append(FormalEdge(id: EvidenceIdentity.id("emitted-edge",from,to,kind),source: from,target: to,kind: kind,attributes: [:]))
        }
        let module = EvidenceIdentity.id("emitted-document",reference.id)
        let path = doc.path.split(separator: "/").last.map(String.init) ?? doc.path
        nodes.append(FormalNode(id: module,kind: "module",label: path,attributes: [:],
            ranges: [FormalEvidence.TextRange(documentID: reference.id,start: 0,end: reference.byteCount)],claimIDs: []))
        roots.append(module)
        for function in artifact.program.functions {
            try Task.checkCancellation()
            let f = function.symbol, root = id(f)
            try node(root,"function",f,IRAddress(programDigest: digest,function: f))
            edge(module,root,"encodes")
            if let first = function.blocks.first { edge(root,id(f,first.id),"entry") }
            for block in function.blocks {
                let b = block.id, blockID = id(f,b)
                try node(blockID,"block",b,IRAddress(programDigest: digest,function: f,block: b))
                var previous: String?
                for (index,instruction) in block.instructions.enumerated() {
                    let step = id(f,b,String(index)), operation: String
                    switch instruction {
                    case .integerLiteral,.literal: operation = "literal"
                    case .integerBinary(_,let op,_,_): operation = op.rawValue
                    case .binary(_,let op,_,_): operation = op.rawValue
                    case .failIf: operation = "failIf"
                    case .aggregate: operation = "aggregate"
                    case .extract: operation = "extract"
                    case .functionRef(_,let symbol): operation = "functionRef"; edge(step,id(symbol),"references")
                    case .call: operation = "call"
                    case .trapIf: operation = "trapIf"
                    case .jump(let target,_): operation = "jump"; edge(step,id(f,target),"jumpsTo")
                    case .branch(_,let yes,_,let no,_): operation = "branch"; edge(step,id(f,yes),"then"); edge(step,id(f,no),"else")
                    case .returnValue: operation = "return"
                    }
                    try node(step,"action",operation,IRAddress(programDigest: digest,function: f,block: b,instruction: index))
                    edge(previous ?? blockID,step,previous == nil ? "startsWith" : "next")
                    previous = step
                }
            }
        }
        guard edges.count <= budget.maximumEdges else { throw FormalEvidenceError.limit("Generated edges exceed graph capacity") }
        let kind: FormalGraphKind = reference.language == "tla" ? .tlaSpecification : .leanDeclarations
        let descriptor = FormalGraphDescriptor(id: graph,kind: kind,roots: roots,artifactDigests: [reference.sha256],
            producer: "swift-formal/emitter",scope: "Control flow encoded in " + doc.path,complete: true,extraction: "available",diagnostics: [])
        try await writer.graph(descriptor)
        try await writer.append(graphID: graph,nodes: nodes,edges: edges)
    }
}
