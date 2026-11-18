import Foundation
import FormalCore
import FormalIR
import FormalEvidence

public struct ModelVerifier: ModelVerifying {
    private let runner: any ToolExecuting
    public init(runner: any ToolExecuting = LocalToolRunner()) { self.runner = runner }

    public func check(artifact: URL, scenario scenarioURL: URL, output: URL, evidenceBudget: EvidenceReadBudget, toolchain: BundledToolchain, timeout: Double = 120) async throws -> FormalVerificationResult {
        guard timeout.isFinite, (1...3600).contains(timeout) else { throw FormalDiagnostic(.invalidArguments, "Timeout must be in 1...3600 seconds") }
        let deadline = VerificationDeadline(seconds: timeout)
        let scenarioData = try ArtifactJSON.readBytes(from: scenarioURL, maximumBytes: 262_144)
        let scenario = try VerificationScenario.decode(scenarioData)
        let snapshot = try await ArtifactSnapshot(artifact)
        let cases = try scenario.cases.map { try ScalarCase($0, program: snapshot.program) }
        let manager = FileManager.default
        let work = output
        guard !manager.fileExists(atPath: work.path) else { throw FormalDiagnostic(.invalidArguments,"Verification output already exists") }
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        try scenarioData.write(to: work.appendingPathComponent("scenario.json"))
        try snapshot.write(to: work)
        let leanRoot = work.appendingPathComponent("lean")
        var environment = toolchain.environment
        environment["LEAN_PATH"] = leanRoot.path
        var observations: [FiniteRunRecord.Case] = []
        var exitCode: Int32 = 0
        var preparationFailure: String?
        do {
            for path in ["SwiftFormal/Runtime", "Generated/Program"] {
                let result = try await invoke(toolchain.lean, ["-M", "1024", "-o", path + ".olean", path + ".lean"], at: leanRoot,
                    environment: environment, log: work.appendingPathComponent(path.replacingOccurrences(of: "/", with: "-")), deadline: deadline)
                guard result.exitCode == 0 else { throw externalFailure(result, message: "Lean module compilation failed; inspect logs") }
            }
        } catch {
            preparationFailure = String(describing: error)
            exitCode = code(error)
        }
        for (index, item) in cases.enumerated() {
            let ir = try IRInterpreter(fuel: scenario.fuel, maximumStackDepth: 512, maximumValueNodes: 100_000, maximumIntegerDigits: 4096)
                .run(snapshot.program, entry: item.specification.entry, arguments: item.arguments)
            let matches = item.matches(ir.outcome)
            if case .boundExceeded(let bound) = ir.outcome {
                observations.append(.init(name: item.specification.name, entry: item.specification.entry, irOutcome: String(describing: ir.outcome),
                    irMatchesExpected: false, tlc: "UNKNOWN", lean: "UNKNOWN", leanAxioms: [], distinctStates: nil, detail: "IR bound exceeded: \(bound); external evaluation skipped"))
                exitCode = merge(exitCode, 6); continue
            }
            if let preparationFailure {
                observations.append(.init(name: item.specification.name, entry: item.specification.entry, irOutcome: String(describing: ir.outcome),
                    irMatchesExpected: matches, tlc: "UNKNOWN", lean: "UNKNOWN", leanAxioms: [], distinctStates: nil, detail: preparationFailure))
                continue
            }
            let caseRoot = work.appendingPathComponent("case-\(index)")
            try manager.createDirectory(at: caseRoot, withIntermediateDirectories: false)
            let tlaRoot = caseRoot.appendingPathComponent("tla")
            try manager.createDirectory(at: tlaRoot, withIntermediateDirectories: false)
            for path in ["Program.tla", "SwiftFormalRuntime.tla"] {
                try snapshot.files["tla/" + path]!.write(to: tlaRoot.appendingPathComponent(path))
            }
            try item.model.write(to: tlaRoot.appendingPathComponent("CaseModel.tla"), atomically: true, encoding: .utf8)
            try "INIT Init\nNEXT Next\nINVARIANT Expected\n".write(to: tlaRoot.appendingPathComponent("CaseModel.cfg"), atomically: true, encoding: .utf8)
            var tlcStatus = "UNKNOWN"; var leanStatus = "UNKNOWN"; var distinct: Int?; var details: [String] = []; var leanAxioms: [String] = []
            do {
                let temporary = tlaRoot.appendingPathComponent("java-tmp")
                try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
                let java = ["-Djava.io.tmpdir=" + temporary.path, "-Xss32m", "-Xmx512m", "-cp", toolchain.jar.path]
                let sany = try await invoke(toolchain.java, java + ["tla2sany.SANY", "CaseModel.tla"], at: tlaRoot,
                    environment: toolchain.environment, log: caseRoot.appendingPathComponent("sany"), deadline: deadline)
                guard sany.exitCode == 0 else { throw externalFailure(sany, message: "SANY rejected the model") }
                try SANYOutputAudit.check(sany.standardOutput + sany.standardError, module: "CaseModel")
                let result = try await invoke(toolchain.java, java + ["tlc2.TLC", "-tool", "-workers", "1", "-cleanup", "-dump", "dot", "trace.dot", "CaseModel"],
                    at: tlaRoot, environment: toolchain.environment, log: caseRoot.appendingPathComponent("tlc"), deadline: deadline)
                let output = result.standardOutput + result.standardError
                if isResourceFailure(output) { throw FormalDiagnostic(.timeout, "TLC exhausted its computation budget") }
                if [2107, 2110, 2114].contains(where: { output.contains("STARTMSG \($0):") }) {
                    tlcStatus = "COUNTEREXAMPLE"; exitCode = merge(exitCode, 5)
                } else {
                    let expression = try NSRegularExpression(pattern: "([0-9]+) distinct states found")
                    let range = NSRange(output.startIndex..., in: output)
                    if let match = expression.matches(in: output, range: range).last, let countRange = Range(match.range(at: 1), in: output) { distinct = Int(output[countRange]) }
                    let reachedTerminal = try await TLCGraphAudit.reachedTerminal(tlaRoot.appendingPathComponent("trace.dot"))
                    guard result.exitCode == 0, output.contains("STARTMSG 2193:"), output.contains("STARTMSG 2186:"),
                          let distinct, distinct > 1, reachedTerminal else { throw FormalDiagnostic(.toolFailure, "TLC did not establish complete nonvacuous exploration and terminal reachability") }
                    tlcStatus = "MODEL_CHECKED"
                }
            } catch {
                exitCode = merge(exitCode, code(error)); details.append(String(describing: error))
            }
            let proof = """
            import Generated.Program
            open SwiftFormal Generated
            set_option maxRecDepth 8192
            set_option maxHeartbeats 1000000
            def observe (entry : String) (actual : List Value) : Option Status := do
              let start ← initial program entry actual
              match evaluate program \(scenario.fuel) start with
              | .terminal final => some final.status
              | _ => none
            \(item.proof)
            """
            let proofURL = leanRoot.appendingPathComponent("Check\(index).lean")
            try proof.write(to: proofURL, atomically: true, encoding: .utf8)
            do {
                let result = try await invoke(toolchain.lean, ["-M", "1024", "-o", proofURL.deletingPathExtension().appendingPathExtension("olean").path, proofURL.path], at: leanRoot, environment: environment,
                    log: caseRoot.appendingPathComponent("lean"), deadline: deadline)
                let output = result.standardOutput + result.standardError
                if result.exitCode != 0, isResourceFailure(output) { throw FormalDiagnostic(.timeout, "Lean exhausted its computation budget") }
                if result.exitCode == 0 {
                    leanAxioms = try LeanProofAudit.check(output, allowed: toolchain.policy.allowedLeanAxioms)
                    leanStatus = "PROVED"
                } else if output.lowercased().contains("tactic `rfl` failed") || output.lowercased().contains("tactic 'rfl' failed") {
                    leanStatus = "UNPROVED"; exitCode = merge(exitCode, matches ? 7 : 5)
                } else { throw FormalDiagnostic(.toolFailure, "Lean did not provide an authorized kernel proof; inspect logs") }
            } catch {
                exitCode = merge(exitCode, code(error)); details.append(String(describing: error))
            }
            if !matches && tlcStatus == "MODEL_CHECKED" && leanStatus == "PROVED" {
                exitCode = merge(exitCode, 7); details.append("IR disagrees with both backend results")
            }
            observations.append(.init(name: item.specification.name, entry: item.specification.entry, irOutcome: String(describing: ir.outcome),
                irMatchesExpected: matches, tlc: tlcStatus, lean: leanStatus, leanAxioms: leanAxioms, distinctStates: distinct, detail: details.joined(separator: "; ")))
        }
        let report = FiniteRunRecord(schemaVersion: 1, scope: "FINITE_GENERATED_MODEL_CASES", translation: "UNVALIDATED",
            artifactDataMatchesIR: true, artifactSHA256: snapshot.hashes, scenarioSHA256: FileDigest.sha256(scenarioData), toolchain: toolchain.policy,
            timeoutSeconds: timeout, fuel: scenario.fuel, cases: observations, exitCode: exitCode, runDirectory: work.path)
        let reportBytes = try ArtifactJSON.encode(report)
        try reportBytes.write(to: work.appendingPathComponent("forensic.json"), options: .atomic)
        let specification = VerificationClaimFactory.artifact(scenarioData,profile: "formal-finite-scenario/1")
        let baseContext = try VerificationClaimFactory.context(snapshot: snapshot,specification: specification,tools: toolchain)
        let collector = try GeneratedEvidenceCollector(work: work,budget: evidenceBudget,runner: runner,tools: toolchain,deadline: deadline)
        do {
            var claims: [VerificationClaim] = []
            for (index,item) in observations.enumerated() {
                let context = EvidenceIdentity.id("finite-obligation",baseContext,String(index),item.name)
                let propositionBytes = try EvidenceIdentity.encode(scenario.cases[index])
                let proposition = String(decoding: propositionBytes,as: UTF8.self)
                let scope = "Named finite generated-model case; fuel \(scenario.fuel)"
                claims.append(VerificationClaimFactory.claim(context: context,obligation: item.name,proposition: proposition,domain: "generatedModel.tla.finite",scope: scope,status: item.tlc,axioms: [],tools: toolchain,artifacts: [snapshot.compilation.sha256,specification.sha256]))
                claims.append(VerificationClaimFactory.claim(context: context,obligation: item.name,proposition: proposition,domain: "generatedModel.lean.finite",scope: scope,status: item.lean,axioms: item.leanAxioms,tools: toolchain,artifacts: [snapshot.compilation.sha256,specification.sha256]))
                let caseRoot = work.appendingPathComponent("case-\(index)"), tlaRoot = caseRoot.appendingPathComponent("tla")
                try await collector.sany(module: "CaseModel",root: tlaRoot,context: context)
                try await collector.tlc(root: tlaRoot,log: caseRoot.appendingPathComponent("tlc.stdout"),context: context,obligation: item.name,complete: item.tlc == "MODEL_CHECKED",counterexample: item.tlc == "COUNTEREXAMPLE")
                try await collector.lean(module: "Check\(index)",declaration: "checkedCase",root: leanRoot,context: context,checked: item.lean == "PROVED")
            }
            let (evidence,graphs) = try await collector.finish(claims: claims)
            let result = FormalVerificationResult(schemaVersion: 1,compilation: snapshot.compilation,compilationEvidence: snapshot.evidence,specification: specification,evidence: evidence,claims: claims,graphs: graphs,diagnostics: observations.filter { !$0.detail.isEmpty }.map { $0.name + ": " + $0.detail },exitCode: exitCode)
            let bytes = try ArtifactJSON.encode(result)
            try bytes.write(to: work.appendingPathComponent("result.json"),options: .atomic)
            return result
        } catch {
            do { try await collector.shutdown() } catch let cleanup { throw FormalDiagnostic(.ioFailure,"Verification failed (\(error)); evidence cleanup failed (\(cleanup))") }
            throw error
        }
    }
    private func invoke(_ executable: URL, _ arguments: [String], at directory: URL, environment: [String: String], log: URL, deadline: VerificationDeadline) async throws -> ToolResult {
        let remaining = try deadline.remaining()
        return try await runner.run(executable: executable, arguments: arguments, directory: directory, environment: environment,
            log: log, timeout: remaining, maximumOutputBytes: 8_388_608, maximumWorkspaceBytes: 536_870_912)
    }
    private func isResourceFailure(_ output: String) -> Bool {
        let text = output.lowercased()
        return ["outofmemoryerror", "stackoverflowerror", "stack overflow", "excessive memory consumption", "maximum memory", "maximum number of heartbeats", "maximum recursion depth", "deep recursion"].contains { text.contains($0) }
    }
    private func externalFailure(_ result: ToolResult, message: String) -> FormalDiagnostic {
        FormalDiagnostic(isResourceFailure(result.standardOutput + result.standardError) ? .timeout : .toolFailure, message)
    }
    private func code(_ error: any Error) -> Int32 {
        if error is CancellationError { return 6 }
        return (error as? FormalDiagnostic)?.exitCode ?? 7
    }
    private func merge(_ current: Int32, _ next: Int32) -> Int32 { max(current, next) }
}
