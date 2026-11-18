import Foundation
import FormalCore
import FormalEvidence

actor GeneratedEvidenceCollector {
    private let writer: EvidenceBundleWriter
    private let budget: EvidenceReadBudget
    private let runner: any ToolExecuting
    private let tools: BundledToolchain
    private let deadline: VerificationDeadline
    private let work: URL
    private var descriptors: [FormalGraphDescriptor] = []

    init(work: URL,budget: EvidenceReadBudget,runner: any ToolExecuting,tools: BundledToolchain,deadline: VerificationDeadline) throws {
        self.work = work; self.budget = budget; self.runner = runner; self.tools = tools; self.deadline = deadline
        writer = try EvidenceBundleWriter(root: work.appendingPathComponent("evidence"),budget: budget,chunkBytes: min(budget.maximumRecordBytes,budget.maximumPageBytes))
    }
    func sany(module: String,root: URL,context: String) async throws {
        let graphID = EvidenceIdentity.id("sany-graph",context,module)
        do {
            var documents: [String:(DocumentReference,Data)] = [:]
            for name in [module,"Program","SwiftFormalRuntime"] {
                let path = root.appendingPathComponent(name + ".tla")
                let document = try await document(path,language: "tla")
                let bytes = try ArtifactJSON.readBytes(from: path,maximumBytes: 16_777_216)
                documents[name + ".tla"] = (document,bytes)
            }
            let helper = try CollectorResources.file("FormalSANY","class")
            let arguments = ["-Djava.io.tmpdir=" + root.appendingPathComponent("java-tmp").path,"-Xmx512m","-Xss32m","-cp",helper.deletingLastPathComponent().path + ":" + tools.jar.path,"FormalSANY",root.appendingPathComponent(module + ".tla").path,String(budget.maximumTraversalNodes)]
            let result = try await invoke(tools.java,arguments,root: root)
            guard result.exitCode == 0 else { throw FormalEvidenceError.io("SANY collector failed: " + result.standardError) }
            let (descriptor,nodes,edges) = try ToolStructureCollector.tla(result.standardOutput,context: context,module: module,documents: documents)
            try await store(descriptor,nodes: nodes,edges: edges)
        } catch { try await unavailable(graphID,kind: .tlaSpecification,context: context,error: error) }
    }
    func lean(module: String,declaration: String,root: URL,context: String,checked: Bool) async throws {
        let graphID = EvidenceIdentity.id("lean-declarations",context,module,declaration)
        let termID = EvidenceIdentity.id("lean-proof-term",context,module,declaration)
        do {
            guard checked else { throw FormalEvidenceError.unsupported("No checked declaration body exists for this obligation") }
            let source = try await document(root.appendingPathComponent(module + ".lean"),language: "lean")
            let compiledDigest = try FileDigest.sha256(root.appendingPathComponent(module + ".olean"))
            let helper = try CollectorResources.file("FormalLean","lean")
            var environment = tools.environment; environment["LEAN_PATH"] = root.path
            let result = try await invoke(tools.lean,["-M","2048","--run",helper.path,tools.root.appendingPathComponent("lean").path,root.path,module,declaration,String(budget.maximumTraversalNodes),String(budget.maximumTraversalNodes)],root: root,environment: environment)
            guard result.exitCode == 0 else { throw FormalEvidenceError.io("Lean collector failed: " + result.standardError + result.standardOutput) }
            let (descriptor,nodes,edges,termDescriptor,terms,termEdges,_) = try ToolStructureCollector.lean(result.standardOutput,context: context,module: module,root: declaration,artifacts: [source.sha256,compiledDigest],allowedAxioms: tools.policy.allowedLeanAxioms)
            try await store(descriptor,nodes: nodes,edges: edges)
            try await store(termDescriptor,nodes: terms,edges: termEdges)
        } catch {
            try await unavailable(graphID,kind: .leanDeclarations,context: context,error: error)
            try await unavailable(termID,kind: .leanProofTerm,context: context,error: error)
        }
    }
    func tlc(root: URL,log: URL,context: String,obligation: String,complete: Bool,counterexample: Bool) async throws {
        let graphID = EvidenceIdentity.id("tlc-state-space",context)
        do {
            var nodes: [FormalNode] = [], edges: [FormalEdge] = [], initial: [String] = [], count = 0
            let graphDigest = try await BoundedRecordLines.read(root.appendingPathComponent("trace.dot"),maximumLineBytes: budget.maximumRecordBytes,maximumTotalBytes: budget.maximumDatabaseBytes) { line in
                guard let record = try TLCDotRecord.parse(line) else { return }
                count += 1
                guard count <= self.budget.maximumTraversalNodes else { throw FormalEvidenceError.limit("TLC observed records") }
                let source = EvidenceIdentity.id("tlc-state",graphID,record.source)
                if let target = record.target {
                    let targetID = EvidenceIdentity.id("tlc-state",graphID,target)
                    edges.append(FormalEdge(id: EvidenceIdentity.id("tlc-transition",graphID,record.source,target,record.label),source: source,target: targetID,kind: "transition",attributes: record.label.isEmpty ? ["actionAvailability":"unavailable"] : ["action":record.label]))
                } else {
                    if record.initial, !initial.contains(source) { initial.append(source) }
                    var decoder = TLAStateDecoder(record.label,maximumDepth: 128)
                    nodes.append(FormalNode(id: source,kind: "state",label: "State " + record.source,attributes: ["fingerprint":record.source,"initial":String(record.initial)],ranges: [],claimIDs: [],stateValue: decoder.decode()))
                }
                if nodes.count == self.budget.maximumNodes || edges.count == self.budget.maximumEdges {
                    try await self.writer.append(graphID: graphID,nodes: nodes,edges: edges); nodes.removeAll(keepingCapacity: true); edges.removeAll(keepingCapacity: true)
                }
            }
            guard count > 0 else { throw FormalEvidenceError.missing("No observed TLC states") }
            try await writer.append(graphID: graphID,nodes: nodes,edges: edges)
            let descriptor = FormalGraphDescriptor(id: graphID,kind: .tlaStateSpace,roots: initial,artifactDigests: [graphDigest],producer: "TLC/tla2tools-1.7.4",scope: complete ? "Complete checked finite model" : "Observed subset of finite model",complete: complete,extraction: "available",diagnostics: [])
            try await writer.graph(descriptor); descriptors.append(descriptor)
        } catch { try await unavailable(graphID,kind: .tlaStateSpace,context: context,error: error) }
        if counterexample { try await trace(log: log,context: context,obligation: obligation) }
    }
    func finish(claims: [VerificationClaim]) async throws -> (EvidenceBundleReference,[FormalGraphDescriptor]) {
        do {
            for claim in claims { try await writer.claim(claim) }
            let reference = try await writer.seal()
            return (reference,descriptors)
        } catch {
            do { try await writer.shutdown() } catch let cleanup { throw FormalEvidenceError.io("Evidence seal failed (\(error)); cleanup failed (\(cleanup))") }
            throw error
        }
    }
    func shutdown() async throws { try await writer.shutdown() }
    private func trace(log: URL,context: String,obligation: String) async throws {
        let graphID = EvidenceIdentity.id("tlc-counterexample",context)
        do {
            let bytes = try ArtifactJSON.readBytes(from: log,maximumBytes: 8_388_608)
            guard let text = String(data: bytes,encoding: .utf8) else { throw FormalEvidenceError.integrity("Invalid TLC trace UTF-8") }
            let trace = try TLCTraceMessages.parse(text)
            guard !trace.steps.isEmpty, trace.steps.count <= budget.maximumTraversalNodes else { throw FormalEvidenceError.missing("Ordered TLC counterexample states unavailable") }
            var states: [String] = [], transitions: [String] = []
            for step in trace.steps {
                let id = EvidenceIdentity.id("tlc-trace-state",graphID,String(step.index)); states.append(id)
                var decoder = TLAStateDecoder(step.text,maximumDepth: 128)
                let node = FormalNode(id: id,kind: "state",label: "Step \(step.index + 1)",attributes: ["index":String(step.index),"observation":step.action],ranges: [],claimIDs: [],stateValue: decoder.decode())
                try await writer.append(graphID: graphID,nodes: [node],edges: [])
                if step.index > 0 {
                    let edge = FormalEdge(id: EvidenceIdentity.id("tlc-trace-edge",graphID,String(step.index - 1)),source: states[step.index-1],target: id,kind: "observedTransition",attributes: ["observation":step.action])
                    transitions.append(edge.id); try await writer.append(graphID: graphID,nodes: [],edges: [edge])
                }
            }
            if let loop = trace.loopBackIndex, let last = states.last {
                let edge = FormalEdge(id: EvidenceIdentity.id("tlc-trace-loop",graphID),source: last,target: states[loop],kind: "loopBack",attributes: [:])
                transitions.append(edge.id); try await writer.append(graphID: graphID,nodes: [],edges: [edge])
            }
            let descriptor = FormalGraphDescriptor(id: graphID,kind: .counterexample,roots: Array(states.prefix(1)),artifactDigests: [EvidenceIdentity.digest(bytes)],producer: "TLC/tla2tools-1.7.4/tool-messages",scope: "Actual ordered violating behavior",complete: true,extraction: "available",diagnostics: [])
            try await writer.graph(descriptor)
            try await writer.trace(FormalTrace(id: EvidenceIdentity.id("tlc-trace",graphID),graphID: graphID,states: states,transitions: transitions,loopBackIndex: trace.loopBackIndex,obligation: obligation,complete: true))
            descriptors.append(descriptor)
        } catch { try await unavailable(graphID,kind: .counterexample,context: context,error: error) }
    }
    private func document(_ path: URL,language: String) async throws -> DocumentReference {
        let bytes = try ArtifactJSON.readBytes(from: path,maximumBytes: 16_777_216)
        let hash = EvidenceIdentity.digest(bytes)
        let id = EvidenceIdentity.id("checked-document",path.lastPathComponent,hash)
        let document = DocumentReference(id: id,sha256: hash,byteCount: bytes.count,language: language,role: "generated")
        try await writer.document(document,bytes: bytes); return document
    }
    private func store(_ descriptor: FormalGraphDescriptor,nodes: [FormalNode],edges: [FormalEdge]) async throws {
        try await writer.graph(descriptor)
        for start in stride(from: 0,to: nodes.count,by: budget.maximumNodes) { try await writer.append(graphID: descriptor.id,nodes: Array(nodes[start..<min(nodes.count,start + budget.maximumNodes)]),edges: []) }
        for start in stride(from: 0,to: edges.count,by: budget.maximumEdges) { try await writer.append(graphID: descriptor.id,nodes: [],edges: Array(edges[start..<min(edges.count,start + budget.maximumEdges)])) }
        descriptors.append(descriptor)
    }
    private func unavailable(_ id: String,kind: FormalGraphKind,context: String,error: any Error) async throws {
        try await writer.discardGraph(id)
        descriptors.removeAll { $0.id == id }
        let descriptor = FormalGraphDescriptor(id: id,kind: kind,artifactDigests: [],producer: "formal-collector/1",scope: "No complete extraction",complete: false,extraction: "unavailable",diagnostics: [String(String(describing: error).prefix(4096))])
        try await writer.graph(descriptor); descriptors.append(descriptor)
    }
    private func invoke(_ executable: URL,_ arguments: [String],root: URL,environment: [String:String]? = nil) async throws -> ToolResult {
        let remaining = try deadline.remaining()
        return try await runner.run(executable: executable,arguments: arguments,directory: root,environment: environment ?? tools.environment,log: work.appendingPathComponent("extract-" + UUID().uuidString),timeout: remaining,maximumOutputBytes: min(8_388_608,budget.maximumPageBytes),maximumWorkspaceBytes: budget.maximumDatabaseBytes)
    }
}
