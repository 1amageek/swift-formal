import Foundation
import FormalCore
import FormalEvidence

public struct FormalInspector: FormalInspecting {
    public init() {}
    public func inspect(_ request: FormalInspectionRequest) async throws -> FormalInspectionResult {
        // This is the embedding host's authorization decision, never decoded from
        // source/log content. Invar must obtain it from its authenticated policy.
        if request.language == .lean && !request.userCodeAuthorized { throw FormalDiagnostic(.unsupportedOperation,"Explicit isolated user-Lean execution authority is required before inspection") }
        guard request.timeout.isFinite, (0.001...3600).contains(request.timeout), request.executionLimits.maximumProcesses == 1, !request.modules.isEmpty, request.files.count <= request.budget.maximumTraversalNodes else { throw FormalEvidenceError.invalid("Inspection bounds") }
        for name in request.modules + (request.declaration.map { [$0] } ?? []) {
            guard !name.isEmpty, name.split(separator: ".",omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 95 } }) else { throw FormalEvidenceError.unsupported("Inspection profile requires explicit qualified scalar module/declaration names") }
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { throw FormalEvidenceError.unsupported("Required enforced inspection sandbox unavailable") }
        let manager = FileManager.default
        guard !manager.fileExists(atPath: request.output.path) else { throw FormalEvidenceError.invalid("Inspection output already exists") }
        let captured = request.output.appendingPathComponent("captured"), compiled = request.output.appendingPathComponent("compiled"), work = request.output.appendingPathComponent("work")
        for path in [captured,compiled,work] { try manager.createDirectory(at: path,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700]) }
        let deadline = ContinuousClock.now.advanced(by: .seconds(request.timeout))
        let journal = try ToolLaunchJournal(directory: request.output.appendingPathComponent("processes"),artifactRoot: request.output)
        let runner = LocalToolRunner(ownership: .isolatedSession,limits: request.executionLimits,journal: journal,workspaceAccountingRoot: request.output)
        let writer = try EvidenceBundleWriter(root: request.output.appendingPathComponent("evidence"),budget: request.budget,chunkBytes: min(request.budget.maximumRecordBytes,request.budget.maximumPageBytes))
        do {
            var total = 0, seen = Set<String>(), documents: [String: (DocumentReference,Data)] = [:]
            for item in request.files {
                guard item.byteCount >= 0, item.byteCount <= request.budget.maximumDatabaseBytes - total, !item.path.hasPrefix("/"), !item.path.split(separator: "/",omittingEmptySubsequences: false).contains(where: { $0.isEmpty || $0 == ".." || $0 == "." }), seen.insert(item.path).inserted else { throw FormalEvidenceError.invalid("Inspection input manifest") }
                let supported = [".tla",".cfg",".lean",".olean",".olean.private",".olean.server",".ilean"].contains { item.path.hasSuffix($0) }
                guard supported else { throw FormalEvidenceError.unsupported("Only declared formal sources and compiled Lean data are admitted") }
                var source = request.inputRoot
                for part in item.path.split(separator: "/") {
                    source.appendPathComponent(String(part))
                    guard try source.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { throw FormalEvidenceError.integrity("Symbolic input path") }
                }
                let attributes = try source.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
                guard attributes.isRegularFile == true, attributes.isSymbolicLink != true, attributes.fileSize == item.byteCount,
                    source.resolvingSymlinksInPath().path.hasPrefix(request.inputRoot.resolvingSymlinksInPath().path + "/") else { throw FormalEvidenceError.integrity("Inspection input path") }
                let bytes = try ArtifactJSON.readBytes(from: source,maximumBytes: max(1,item.byteCount))
                guard bytes.count == item.byteCount, EvidenceIdentity.digest(bytes) == item.sha256 else { throw FormalEvidenceError.integrity("Inspection input changed") }; total += bytes.count
                let destination = captured.appendingPathComponent(item.path)
                try manager.createDirectory(at: destination.deletingLastPathComponent(),withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700]); try bytes.write(to: destination)
                if item.path.hasSuffix(".lean") || item.path.hasSuffix(".tla") || item.path.hasSuffix(".cfg") {
                    let document = DocumentReference(id: EvidenceIdentity.id("inspection-document",item.path,item.sha256),sha256: item.sha256,byteCount: bytes.count,language: request.language.rawValue,role: "original")
                    try await writer.document(document,bytes: bytes); documents[item.path] = (document,bytes)
                }
            }
            let manifestBytes = try EvidenceIdentity.encode(request.files.sorted { $0.path < $1.path })
            let collectors = try CollectorResources.identity()
            let context = EvidenceIdentity.id("inspection-context",EvidenceIdentity.digest(manifestBytes),request.toolchain.policy.inventorySHA256,collectors)
            var graphs: [FormalGraphDescriptor] = [], claims: [VerificationClaim] = []
            if request.language == .tla {
                let module = request.modules.last!
                guard seen.contains(module + ".tla") else { throw FormalEvidenceError.missing("Explicit TLA root file") }
                let result = try await run(runner,request: request,executable: request.toolchain.java,arguments: ["-Xmx512m","-XX:-UsePerfData","-Djava.io.tmpdir=" + work.path,"-cp",try CollectorResources.file("FormalSANY","class").deletingLastPathComponent().path + ":" + request.toolchain.jar.path,"FormalSANY",captured.appendingPathComponent(module + ".tla").path,String(request.budget.maximumTraversalNodes)],directory: captured,readRoots: [captured],writeRoot: work,deadline: deadline)
                guard result.exitCode == 0 else { throw FormalEvidenceError.io("SANY rejected inspection (exit \(result.exitCode)): " + result.standardError + result.standardOutput) }
                let (descriptor,nodes,edges) = try ToolStructureCollector.tla(result.standardOutput,context: context,module: module,documents: documents)
                try await append(descriptor,nodes: nodes,edges: edges,to: writer,budget: request.budget); graphs = [descriptor]
            } else {
                guard let declaration = request.declaration, let module = request.modules.last else { throw FormalEvidenceError.invalid("Lean inspection requires a declaration") }
                var environment = request.toolchain.environment
                environment["LEAN_PATH"] = compiled.path + ":" + captured.path
                for (index,name) in request.modules.enumerated() {
                    let relative = name.replacingOccurrences(of: ".",with: "/")
                    guard seen.contains(relative + ".lean") else { throw FormalEvidenceError.missing("Declared Lean module source") }
                    let directory = work.appendingPathComponent("compile-" + String(index))
                    try manager.createDirectory(at: directory,withIntermediateDirectories: false,attributes: [.posixPermissions: 0o700])
                    let output = directory.appendingPathComponent("Module.olean")
                    let result = try await run(runner,request: request,executable: request.toolchain.lean,arguments: ["-R",captured.path,"-M","2048","-o",output.path,captured.appendingPathComponent(relative + ".lean").path],directory: directory,readRoots: [captured,compiled],writeRoot: directory,environment: environment,deadline: deadline)
                    guard result.exitCode == 0 else { throw FormalEvidenceError.io("Lean source elaboration failed (exit \(result.exitCode)): " + result.standardError + result.standardOutput) }
                    for suffix in ["",".private",".server"] {
                        let file = URL(fileURLWithPath: output.path + suffix)
                        if manager.fileExists(atPath: file.path) {
                            let destination = compiled.appendingPathComponent(relative + ".olean" + suffix)
                            try manager.createDirectory(at: destination.deletingLastPathComponent(),withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700]); try manager.copyItem(at: file,to: destination)
                        }
                    }
                }
                let result = try await run(runner,request: request,executable: request.toolchain.lean,arguments: ["-M","2048","--run",try CollectorResources.file("FormalLean","lean").path,request.toolchain.root.appendingPathComponent("lean").path,compiled.path,module,declaration,String(request.budget.maximumTraversalNodes),String(request.budget.maximumTraversalNodes)],directory: work,readRoots: [captured,compiled],writeRoot: work,environment: environment,deadline: deadline)
                guard result.exitCode == 0 else { throw FormalEvidenceError.io("Independent Lean kernel replay/inspection failed: " + result.standardError + result.standardOutput) }
                let compiledRoot = compiled.appendingPathComponent(module.replacingOccurrences(of: ".",with: "/") + ".olean")
                let compiledDigest = try FileDigest.sha256(compiledRoot)
                let (descriptor,nodes,edges,termDescriptor,terms,termEdges,observed) = try ToolStructureCollector.lean(result.standardOutput,context: context,module: module,root: declaration,artifacts: request.files.map(\.sha256) + [compiledDigest],allowedAxioms: request.toolchain.policy.allowedLeanAxioms)
                try await append(descriptor,nodes: nodes,edges: edges,to: writer,budget: request.budget)
                try await append(termDescriptor,nodes: terms,edges: termEdges,to: writer,budget: request.budget)
                let claim = VerificationClaim(id: EvidenceIdentity.id("lean-claim",context,module,declaration),obligation: declaration,proposition: "Kernel-accepted declaration " + module + "." + declaration,assumptions: observed.axioms,domain: "leanKernel",scope: "Exact captured Lean module closure",execution: "completed",outcome: nodes.first(where: { $0.label == declaration })?.kind == "theorem" ? "proved" : "notEvaluated",translation: "notApplicable",toolIdentities: ["toolchain":request.toolchain.policy.inventorySHA256,"collectors":try CollectorResources.identity()],artifactDigests: request.files.map(\.sha256))
                try await writer.claim(claim); claims = [claim]; graphs = [descriptor,termDescriptor]
            }
            let reference = try await writer.seal()
            return FormalInspectionResult(schemaVersion: 1,evidence: reference,graphs: graphs,claims: claims)
        } catch {
            do { try await writer.shutdown() } catch let cleanup { throw FormalEvidenceError.io("Inspection failed: \(error); cleanup failed: \(cleanup)") }
            throw error
        }
    }
    private func append(_ descriptor: FormalGraphDescriptor,nodes: [FormalNode],edges: [FormalEdge],to writer: EvidenceBundleWriter,budget: EvidenceReadBudget) async throws {
        try await writer.graph(descriptor)
        var index = 0
        while index < nodes.count { let end = min(nodes.count,index + budget.maximumNodes); try await writer.append(graphID: descriptor.id,nodes: Array(nodes[index..<end]),edges: []); index = end }
        index = 0
        while index < edges.count { let end = min(edges.count,index + budget.maximumEdges); try await writer.append(graphID: descriptor.id,nodes: [],edges: Array(edges[index..<end])); index = end }
    }
    private func run(_ runner: any ToolExecuting,request: FormalInspectionRequest,executable: URL,arguments: [String],directory: URL,readRoots: [URL],writeRoot: URL,environment: [String: String]? = nil,deadline: ContinuousClock.Instant) async throws -> ToolResult {
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let seconds = Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18
        guard seconds > 0 else { throw FormalDiagnostic(.timeout,"Whole inspection deadline expired") }
        let helper = try CollectorResources.file("FormalLean","lean").deletingLastPathComponent()
        var policy = try InspectionSandbox.profile(read: [request.toolchain.root,helper] + readRoots,write: writeRoot)
        // The pinned JRE's getpwuid bootstrap needs this one OS directory service.
        // Arbitrary Mach lookup remains denied, including for user Lean code.
        if executable == request.toolchain.java { policy += "\n(allow mach-lookup (global-name \"com.apple.system.opendirectoryd.libinfo\"))" }
        return try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),arguments: ["-p",policy,executable.path] + arguments,directory: directory,environment: environment ?? request.toolchain.environment,log: request.output.appendingPathComponent("tool-" + UUID().uuidString),timeout: seconds,maximumOutputBytes: request.budget.maximumPageBytes,maximumWorkspaceBytes: request.budget.maximumDatabaseBytes)
    }
}
