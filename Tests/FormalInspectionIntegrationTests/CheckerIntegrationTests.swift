import Foundation
import Testing
import FormalCore
import FormalCompiler
import FormalEvidence
@testable import FormalValidation

@Suite(.timeLimit(.minutes(1)), .enabled(if: ProcessInfo.processInfo.environment["FORMAL_INSPECTION_TOOLCHAIN"] != nil))
struct CheckerIntegrationTests {
    let budget = EvidenceReadBudget(maximumDatabaseBytes: 134_217_728,maximumRecordBytes: 262_144,maximumPageBytes: 8_388_608,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 16)
    @Test func actualFiniteCheckerPublishesStatesDependenciesAndCounterexampleOrder() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let tools = try InspectionIntegrationTests().tools()
        let source = Data("def f(a: int) -> int:\n    return a + 1\n".utf8)
        let compilation = try CompilationArtifactGenerator().generate(CompilationRequest(source: source,language: .python,moduleID: "Probe",evidenceBudget: budget))
        let artifact = root.appendingPathComponent("artifact")
        _ = try await compilation.write(to: artifact)
        let specification = root.appendingPathComponent("scenario.json")
        let scenario = #"{"schemaVersion":1,"fuel":32,"cases":[{"name":"positive","entry":"f","arguments":["2"],"expected":{"status":"returned","value":"3"}},{"name":"negative","entry":"f","arguments":["2"],"expected":{"status":"returned","value":"4"}}]}"#
        try Data(scenario.utf8).write(to: specification)
        let output = root.appendingPathComponent("result")
        let result = try await ModelVerifier().check(artifact: artifact,scenario: specification,output: output,evidenceBudget: budget,toolchain: tools,timeout: 50)
        #expect(result.exitCode == 5)
        #expect(result.claims.contains { $0.obligation == "positive" && $0.outcome == "proved" })
        #expect(result.claims.contains { $0.obligation == "positive" && $0.outcome == "modelChecked" })
        #expect(result.claims.contains { $0.obligation == "negative" && $0.outcome == "counterexample" })
        #expect(result.claims.allSatisfy { $0.translation == "UNVALIDATED" })
        let reader = try await LocalFormalEvidenceStore(root: output.appendingPathComponent("evidence")).open(result.evidence,budget: budget)
        let catalog = try await reader.catalog()
        #expect(catalog.claims == result.claims.sorted { $0.id < $1.id })
        let stateGraph = try #require(result.graphs.first { $0.kind == .tlaStateSpace && $0.complete })
        let page = try await reader.graph(FormalGraphQuery(graphID: stateGraph.id,roots: [],relations: [],direction: "both",depth: 0))
        #expect(page.nodes.contains { $0.stateValue != nil } && !page.edges.isEmpty)
        #expect(result.graphs.contains { $0.kind == .leanDeclarations && $0.extraction == "available" }, "\(result.graphs)")
        #expect(result.graphs.contains { $0.kind == .tlaSpecification && $0.extraction == "available" }, "\(result.graphs)")
        let traceID = try #require(catalog.traces.first)
        let trace = try await reader.trace(FormalTraceQuery(traceID: traceID,start: 0,count: 100))
        #expect(trace.states.count > 1 && trace.transitions.count == trace.states.count - 1 && trace.complete)
        try await reader.shutdown()
    }
    @Test func extractionFailureDoesNotRewriteAnActualProof() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let tools = try InspectionIntegrationTests().tools()
        let artifact = root.appendingPathComponent("artifact")
        let compilation = try CompilationArtifactGenerator().generate(CompilationRequest(source: Data("def identity(a: int) -> int:\n    return a\n".utf8),language: .python,moduleID: "Probe",evidenceBudget: budget))
        _ = try await compilation.write(to: artifact)
        let specification = root.appendingPathComponent("properties.json")
        let property = #"{"schemaVersion":1,"properties":[{"name":"identity","entry":"identity","inputViews":["integer"],"resultView":"integer","requires":"true","ensures":"result == arg0"}]}"#
        try Data(property.utf8).write(to: specification)
        let result = try await PropertyVerifier(runner: FailingExtractor()).check(artifact: artifact,properties: specification,output: root.appendingPathComponent("result"),evidenceBudget: budget,toolchain: tools,timeout: 40)
        #expect(result.exitCode == 0)
        #expect(result.claims.count == 1 && result.claims[0].outcome == "proved")
        #expect(result.graphs.allSatisfy { $0.extraction == "unavailable" && !$0.complete })
    }
    private struct FailingExtractor: ToolExecuting {
        func run(executable: URL,arguments: [String],directory: URL,environment: [String:String],log: URL,timeout: Double,maximumOutputBytes: Int,maximumWorkspaceBytes: Int?) async throws -> ToolResult {
            if arguments.contains("--run") || arguments.contains("FormalSANY") { throw FormalDiagnostic(.toolFailure,"Injected optional collector failure") }
            return try await LocalToolRunner().run(executable: executable,arguments: arguments,directory: directory,environment: environment,log: log,timeout: timeout,maximumOutputBytes: maximumOutputBytes,maximumWorkspaceBytes: maximumWorkspaceBytes)
        }
    }
}

extension CheckerIntegrationTests {
    @Test func actualTLCLivenessWitnessRetainsItsObservedLoop() async throws {
        let tools = try InspectionIntegrationTests().tools()
        for next in ["x' = 1 - x","UNCHANGED x"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root,withIntermediateDirectories: false)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let model = "---- MODULE Loop ----\nEXTENDS Integers\nVARIABLE x\nInit == x = 0\nNext == \(next)\nSpec == Init /\\ [][Next]_x\nLive == <>(x = 2)\n====\n"
            try Data(model.utf8).write(to: root.appendingPathComponent("Loop.tla"))
            try Data("SPECIFICATION Spec\nPROPERTY Live\n".utf8).write(to: root.appendingPathComponent("Loop.cfg"))
            let result = try await LocalToolRunner().run(executable: tools.java,arguments: ["-Xmx512m","-XX:-UsePerfData","-cp",tools.jar.path,"tlc2.TLC","-tool","-workers","1","-cleanup","-dump","dot","trace.dot","Loop"],directory: root,environment: tools.environment,log: root.appendingPathComponent("tlc"),timeout: 15,maximumOutputBytes: 8_388_608,maximumWorkspaceBytes: 64 * 1024 * 1024)
            #expect(result.exitCode != 0)
            let log = root.appendingPathComponent("observed.txt")
            try Data(result.standardOutput.utf8).write(to: log)
            let actual = try TLCTraceMessages.parse(result.standardOutput)
            #expect(!actual.steps.isEmpty && actual.loopBackIndex != nil)
            let output = root.appendingPathComponent("collection")
            try FileManager.default.createDirectory(at: output,withIntermediateDirectories: false)
            let collector = try GeneratedEvidenceCollector(work: output,budget: budget,runner: LocalToolRunner(),tools: tools,deadline: VerificationDeadline(seconds: 10))
            try await collector.tlc(root: root,log: log,context: EvidenceIdentity.digest(Data(model.utf8)),obligation: "Live",complete: false,counterexample: true)
            let (reference,graphs) = try await collector.finish(claims: [])
            #expect(graphs.contains { $0.kind == .counterexample && $0.extraction == "available" })
            let reader = try await LocalFormalEvidenceStore(root: output.appendingPathComponent("evidence")).open(reference,budget: budget)
            let catalog = try await reader.catalog(), id = try #require(catalog.traces.first)
            let trace = try await reader.trace(FormalTraceQuery(traceID: id,start: 0,count: 100))
            #expect(trace.loopBackIndex == actual.loopBackIndex)
            #expect(trace.states.count == actual.steps.count && trace.transitions.count == trace.states.count)
            let graph = try #require(graphs.first { $0.kind == .counterexample })
            let page = try await reader.graph(FormalGraphQuery(graphID: graph.id,roots: [],relations: [],direction: "both",depth: 0))
            #expect(page.edges.contains { $0.kind == "loopBack" && $0.source == trace.states.last && $0.target == trace.states[actual.loopBackIndex!] })
            try await reader.shutdown()
        }
    }
}
