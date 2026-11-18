import Foundation
import Testing
import FormalCore
import FormalEvidence
@testable import FormalValidation

@Suite(.timeLimit(.minutes(1)), .enabled(if: ProcessInfo.processInfo.environment["FORMAL_INSPECTION_TOOLCHAIN"] != nil))
struct InspectionIntegrationTests {
    let budget = EvidenceReadBudget(maximumDatabaseBytes: 64 * 1024 * 1024,maximumRecordBytes: 262_144,maximumPageBytes: 8_388_608,maximumNodes: 500,maximumEdges: 1500,maximumTraversalNodes: 100_000,maximumCursors: 16)
    func tools() throws -> BundledToolchain {
        let path = try #require(ProcessInfo.processInfo.environment["FORMAL_INSPECTION_TOOLCHAIN"])
        return try PinnedToolchain().verify(at: URL(fileURLWithPath: path))
    }
    func fixture(_ source: String,language: FormalInspectionRequest.Language,root: URL,authorized: Bool,modules: [String] = ["Probe"],declaration: String? = "root",toolchain: BundledToolchain? = nil) throws -> FormalInspectionRequest {
        let input = root.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        let bytes = Data(source.utf8), path = "Probe." + (language == .lean ? "lean" : "tla")
        try bytes.write(to: input.appendingPathComponent(path))
        let selectedTools: BundledToolchain
        if let toolchain { selectedTools = toolchain } else { selectedTools = try tools() }
        return FormalInspectionRequest(language: language,inputRoot: input,files: [InspectionInputFile(path: path,sha256: EvidenceIdentity.digest(bytes),byteCount: bytes.count)],modules: modules,declaration: declaration,output: root.appendingPathComponent("output"),toolchain: selectedTools,timeout: 30,budget: budget,executionLimits: ToolProcessLimits(maximumResidentBytes: 2_147_483_648,maximumProcesses: 1,maximumCPUSeconds: 30),userCodeAuthorized: authorized)
    }
    @Test func actualSANYAndLeanDependencies() async throws {
        for language in [FormalInspectionRequest.Language.tla,.lean] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let source = language == .lean ? "def base : Nat := 3\ntheorem lemma : base = 3 := rfl\ntheorem root : base = 3 := lemma\n" : "---- MODULE Probe ----\nEXTENDS Naturals\nVARIABLE x\nInit == x = 0\nNext == x' = x + 1\nSafe == x >= 0\n====\n"
            let request = try fixture(source,language: language,root: root,authorized: language == .lean)
            let result = try await FormalInspector().inspect(request)
            let reader = try await LocalFormalEvidenceStore(root: request.output.appendingPathComponent("evidence")).open(result.evidence,budget: budget)
            let descriptor = try #require(result.graphs.first)
            var cursor: String?, nodes: [String: FormalNode] = [:], edges: [FormalEdge] = []
            repeat {
                let page = try await reader.graph(FormalGraphQuery(graphID: descriptor.id,roots: [],relations: [],direction: "both",depth: 0,cursor: cursor))
                for node in page.nodes { nodes[node.id] = node }; edges += page.edges; cursor = page.nextCursor
            } while cursor != nil
            if language == .lean {
                #expect(result.claims.first?.outcome == "proved")
                #expect(edges.contains { $0.kind == "valueUses" && nodes[$0.source]?.label == "root" && nodes[$0.target]?.label == "lemma" })
                #expect(edges.contains { $0.kind == "typeUses" && nodes[$0.source]?.label == "root" && nodes[$0.target]?.label == "base" })
                #expect(result.graphs.contains { $0.kind == .leanProofTerm && $0.extraction == "available" })
            } else {
                #expect(result.claims.isEmpty)
                #expect(nodes.values.contains { $0.kind == "variable" && $0.label == "x" })
                #expect(edges.contains { $0.kind == "references" && nodes[$0.source]?.label == "Next" && nodes[$0.target]?.label == "x" })
            }
            try await reader.shutdown()
        }
    }
    @Test func permissionRefusalPrecedesElaboration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let request = try fixture("#eval IO.println \"Should not execute\"\ntheorem root : True := True.intro\n",language: .lean,root: root,authorized: false)
        await #expect(throws: FormalDiagnostic.self) { try await FormalInspector().inspect(request) }
        #expect(!FileManager.default.fileExists(atPath: request.output.path))
    }
    @Test func actualUserLeanCannotWriteOutsideOrFork() async throws {
        let tools = try tools()
        for operation in ["write","fork"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let outside = root.appendingPathComponent("outside")
            let code = operation == "write" ? "#eval IO.FS.writeFile \"\(outside.path)\" \"escaped\"" : "#eval (IO.Process.output {cmd := \"\(tools.lean.path)\",args := #[\"--version\"]}) >>= fun output => IO.println output.exitCode"
            let request = try fixture(code + "\ntheorem root : True := True.intro\n",language: .lean,root: root,authorized: true,toolchain: tools)
            do { _ = try await FormalInspector().inspect(request); Issue.record("Sandbox escape succeeded") }
            catch {
                let text = String(describing: error).lowercased()
                #expect(text.contains("not permitted") || text.contains("permission denied"), "Unexpected failure: \(text)")
            }
            #expect(!FileManager.default.fileExists(atPath: outside.path))
        }
    }
}

extension InspectionIntegrationTests {
    @Test func actualKernelRefusesAdmissionsAndCustomAxioms() async throws {
        let tools = try tools()
        for source in ["theorem root : False := by sorry\n", "axiom untrusted : False\ntheorem root : False := untrusted\n"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
            let request = try fixture(source,language: .lean,root: root,authorized: true,toolchain: tools)
            do { _ = try await FormalInspector().inspect(request); Issue.record("Unapproved proof was accepted") }
            catch { #expect(String(describing: error).contains("axiom audit rejected"), "Unexpected failure: \(error)") }
        }
    }
    @Test func actualImportedInitializerDoesNotRunDuringIndependentReplay() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let source = "initialize marker : Unit ← IO.FS.writeFile \"initializer-ran\" \"elaboration\"\ndef base : Nat := 1\n"
        let initial = try fixture(source,language: .lean,root: root,authorized: true)
        let rootBytes = Data("import Probe\ntheorem root : base = 1 := rfl\n".utf8)
        try rootBytes.write(to: initial.inputRoot.appendingPathComponent("Root.lean"))
        let files = initial.files + [InspectionInputFile(path: "Root.lean",sha256: EvidenceIdentity.digest(rootBytes),byteCount: rootBytes.count)]
        let request = FormalInspectionRequest(language: .lean,inputRoot: initial.inputRoot,files: files,modules: ["Probe","Root"],declaration: "root",output: initial.output,toolchain: initial.toolchain,timeout: 30,budget: budget,executionLimits: initial.executionLimits,userCodeAuthorized: true)
        let result = try await FormalInspector().inspect(request)
        #expect(result.claims.first?.outcome == "proved")
        #expect(FileManager.default.fileExists(atPath: request.output.appendingPathComponent("work/compile-1/initializer-ran").path))
        #expect(!FileManager.default.fileExists(atPath: request.output.appendingPathComponent("work/initializer-ran").path))
    }

    @Test func actualInspectionSandboxDeniesNativeNetworkSyscall() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: false)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let code = "#include <sys/socket.h>\n#include <netinet/in.h>\n#include <arpa/inet.h>\n#include <errno.h>\n#include <unistd.h>\nint main(void) { int fd = socket(AF_INET, SOCK_STREAM, 0); if (fd < 0) return 3; struct sockaddr_in peer = {0}; peer.sin_family = AF_INET; peer.sin_port = htons(9); peer.sin_addr.s_addr = htonl(INADDR_LOOPBACK); int result = connect(fd, (const struct sockaddr *)&peer, sizeof(peer)); int reason = errno; close(fd); return result < 0 && (reason == EPERM || reason == EACCES) ? 0 : 2; }\n"
        let source = root.appendingPathComponent("probe.c"), binary = root.appendingPathComponent("probe")
        try Data(code.utf8).write(to: source)
        let runner = LocalToolRunner()
        let built = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/clang"),arguments: [source.path,"-o",binary.path],directory: root,environment: ["PATH":"/usr/bin:/bin"],log: root.appendingPathComponent("build"),timeout: 15,maximumOutputBytes: 1_048_576,maximumWorkspaceBytes: 16_777_216)
        #expect(built.exitCode == 0)
        let policy = try InspectionSandbox.profile(read: [root],write: root)
        let checked = try await runner.run(executable: URL(fileURLWithPath: "/usr/bin/sandbox-exec"),arguments: ["-p",policy,binary.path],directory: root,environment: [:],log: root.appendingPathComponent("checked"),timeout: 5,maximumOutputBytes: 65_536,maximumWorkspaceBytes: 16_777_216)
        #expect(checked.exitCode == 0, "exit=\(checked.exitCode) \(checked.standardError)")
    }
}

extension InspectionIntegrationTests {
    @Test func actualSANYIncludesInstanceAndNestedModuleClosure() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let source = "---- MODULE Probe ----\n---- MODULE Inner ----\nCONSTANT c\nValue == c\n====\nI == INSTANCE Inner WITH c <- 1\nRoot == I!Value\n====\n"
        let request = try fixture(source,language: .tla,root: root,authorized: false)
        let result = try await FormalInspector().inspect(request)
        let reader = try await LocalFormalEvidenceStore(root: request.output.appendingPathComponent("evidence")).open(result.evidence,budget: budget)
        let graph = try #require(result.graphs.first)
        let page = try await reader.graph(FormalGraphQuery(graphID: graph.id,roots: [],relations: [],direction: "both",depth: 0,cursor: nil))
        let inner = try #require(page.nodes.first { $0.kind == "module" && $0.label == "Inner" })
        let instance = try #require(page.nodes.first { $0.kind == "moduleInstance" && $0.label == "I" })
        #expect(page.edges.contains { $0.source == instance.id && $0.target == inner.id && $0.kind == "instantiates" })
        #expect(page.edges.contains { $0.target == inner.id && $0.kind == "contains" })
        #expect(graph.extraction == "available")
        try await reader.shutdown()
    }
}
