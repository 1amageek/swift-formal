import FormalCore
import FormalIR
import FormalEvidence

struct CompilationIRGraph {
    static func write(_ program: IRProgram,to writer: EvidenceBundleWriter,budget: EvidenceReadBudget) async throws {
        let bytes = try ArtifactJSON.encode(program), digest = EvidenceIdentity.digest(bytes)
        let graph = EvidenceIdentity.id("ir-control-flow",digest)
        func id(_ function: String,_ block: String = "",_ instruction: String = "") -> String { EvidenceIdentity.id("ir-node",digest,function,block,instruction) }
        let roots = program.functions.map { id($0.symbol) }
        try await writer.graph(FormalGraphDescriptor(id: graph,kind: .irControlFlow,roots: roots,artifactDigests: [digest],producer: "FormalIR/1",scope: "Exact generated IR; source correspondence UNVALIDATED",complete: true,extraction: "available",diagnostics: []))
        var nodes: [FormalNode] = [], edges: [FormalEdge] = []
        func edge(_ source: String,_ target: String,_ kind: String) -> FormalEdge { FormalEdge(id: EvidenceIdentity.id("ir-edge",graph,source,target,kind),source: source,target: target,kind: kind,attributes: [:]) }
        for function in program.functions {
            let functionID = id(function.symbol)
            nodes.append(FormalNode(id: functionID,kind: "function",label: function.symbol,attributes: ["module":function.moduleID],ranges: [],claimIDs: []))
            for block in function.blocks {
                let blockID = id(function.symbol,block.id)
                nodes.append(FormalNode(id: blockID,kind: "block",label: block.id,attributes: [:],ranges: [],claimIDs: [])); edges.append(edge(functionID,blockID,"contains"))
                for (index,instruction) in block.instructions.enumerated() {
                    try Task.checkCancellation()
                    let instructionID = id(function.symbol,block.id,String(index))
                    let encoded = try ArtifactJSON.encode(instruction)
                    nodes.append(FormalNode(id: instructionID,kind: "instruction",label: instruction.destination ?? "control",attributes: ["instruction":String(decoding: encoded,as: UTF8.self)],ranges: [],claimIDs: []))
                    edges.append(edge(blockID,instructionID,"contains"))
                    if index > 0 { edges.append(edge(id(function.symbol,block.id,String(index-1)),instructionID,"next")) }
                    switch instruction {
                    case .jump(let target,_): edges.append(edge(instructionID,id(function.symbol,target),"jumpsTo"))
                    case .branch(_,let yes,_,let no,_): edges.append(edge(instructionID,id(function.symbol,yes),"then")); edges.append(edge(instructionID,id(function.symbol,no),"else"))
                    case .functionRef(_,let symbol): edges.append(edge(instructionID,id(symbol),"references"))
                    default: break
                    }
                    if nodes.count >= budget.maximumNodes - 2 || edges.count >= budget.maximumEdges - 4 {
                        try await writer.append(graphID: graph,nodes: nodes,edges: edges); nodes.removeAll(keepingCapacity: true); edges.removeAll(keepingCapacity: true)
                    }
                }
            }
        }
        if !nodes.isEmpty || !edges.isEmpty { try await writer.append(graphID: graph,nodes: nodes,edges: edges) }
    }
}
