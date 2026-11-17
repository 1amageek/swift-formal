import Foundation
import FormalCore
import FormalIR

public struct PropertyVerifier: PropertyVerifying {
    private let runner: any ToolExecuting
    public init(runner: any ToolExecuting = LocalToolRunner()) { self.runner = runner }

    public func check(artifact: URL, properties specificationURL: URL, toolchain: BundledToolchain, timeout: Double = 120) async throws -> PropertyVerificationReport {
        guard timeout.isFinite, (1...3600).contains(timeout) else { throw PropertySpecification.invalid("Timeout must be in 1...3600 seconds") }
        let data = try ArtifactJSON.readBytes(from: specificationURL, maximumBytes: 262_144)
        let specification = try PropertySpecification.decode(data)
        let snapshot = try ArtifactSnapshot(artifact)
        let properties = try specification.properties.map { try BoundProperty($0, program: snapshot.program) }
        let manager = FileManager.default
        let work = artifact.appendingPathComponent("verification/\(UUID().uuidString)")
        try manager.createDirectory(at: work, withIntermediateDirectories: true)
        try data.write(to: work.appendingPathComponent("properties.json"))
        try snapshot.write(to: work)
        let leanRoot = work.appendingPathComponent("lean")
        var environment = toolchain.environment; environment["LEAN_PATH"] = leanRoot.path
        var preparationError: (String, Int32)?
        do {
            for name in ["SwiftFormal/Runtime", "Generated/Program"] {
                let result = try await invoke(toolchain.lean, ["-M", "2048", "-o", name + ".olean", name + ".lean"], at: leanRoot,
                    environment: environment, log: work.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-")), timeout: timeout)
                guard result.exitCode == 0 else { throw failure(result, message: "Lean module preparation failed; inspect logs") }
            }
        } catch { preparationError = (String(describing: error), code(error)) }
        var records: [PropertyVerificationReport.Property] = []; var exitCode: Int32 = 0
        for (index, property) in properties.enumerated() {
            let directory = work.appendingPathComponent("property-\(index)")
            let tlaRoot = directory.appendingPathComponent("tla")
            try manager.createDirectory(at: tlaRoot, withIntermediateDirectories: true)
            try manager.createDirectory(at: tlaRoot.appendingPathComponent("java-tmp"), withIntermediateDirectories: false)
            for path in ["Program.tla", "SwiftFormalRuntime.tla"] { try snapshot.files["tla/" + path]!.write(to: tlaRoot.appendingPathComponent(path)) }
            let model = PropertyTLAEmitter().emit(property)
            try model.write(to: tlaRoot.appendingPathComponent("Universal.tla"), atomically: true, encoding: .utf8)
            var status = "UNKNOWN"; var lean = "UNKNOWN"; var tla = "NOT_PARSED"
            var bound: Int?; var cuts: Int?; var axioms: [String] = []; var witnessValues: [String]?; var witnessTLC: String?
            var detail: [String] = []; var seconds: [String: Double] = [:]; var propertyExit: Int32 = 6
            if let preparationError {
                detail.append(preparationError.0); propertyExit = preparationError.1
            } else {
                do {
                    let sany = try await runSANY("Universal", at: tlaRoot, tools: toolchain, log: directory.appendingPathComponent("sany"), timeout: timeout)
                    seconds["sany"] = sany.elapsedSeconds; tla = "SPECIFICATION_GENERATED"
                    let executionBound = try PropertyExecutionBound.derive(snapshot.program, entry: property.specification.entry)
                    bound = executionBound
                    let candidate = try PropertyWitnessSearch().find(property, program: snapshot.program, bound: executionBound)
                    if let candidate {
                        let proof = PropertyLeanEmitter().counterexample(property, bound: executionBound, witness: candidate)
                        let proofURL = leanRoot.appendingPathComponent("Counterexample\(index).lean")
                        try proof.write(to: proofURL, atomically: true, encoding: .utf8)
                        let checked = try await invoke(toolchain.lean, ["-M", "2048", proofURL.path], at: leanRoot, environment: environment,
                            log: directory.appendingPathComponent("counterexample-lean"), timeout: timeout)
                        seconds["counterexampleLean"] = checked.elapsedSeconds
                        guard checked.exitCode == 0 else { throw failure(checked, message: "Candidate counterexample was not kernel checked") }
                        axioms = try LeanProofAudit.check(checked.standardOutput + checked.standardError, allowed: toolchain.policy.allowedLeanAxioms, theoremName: "checkedCounterexample")
                        let witnessModel = PropertyTLAEmitter().witness(property, candidate)
                        try witnessModel.write(to: tlaRoot.appendingPathComponent("Witness.tla"), atomically: true, encoding: .utf8)
                        try "INIT Init\nNEXT Next\nINVARIANT NotWitness\n".write(to: tlaRoot.appendingPathComponent("Witness.cfg"), atomically: true, encoding: .utf8)
                        _ = try await runSANY("Witness", at: tlaRoot, tools: toolchain, log: directory.appendingPathComponent("witness-sany"), timeout: timeout)
                        let checkedTLC = try await invoke(toolchain.java, javaArguments(toolchain, at: tlaRoot) + ["tlc2.TLC", "-tool", "-workers", "1", "-cleanup", "-dump", "dot", "trace.dot", "Witness"],
                            at: tlaRoot, environment: toolchain.environment, log: directory.appendingPathComponent("counterexample-tlc"), timeout: timeout)
                        seconds["counterexampleTLC"] = checkedTLC.elapsedSeconds
                        let output = checkedTLC.standardOutput + checkedTLC.standardError
                        guard checkedTLC.exitCode != 0, output.contains("STARTMSG 2110:"), output.contains("Invariant NotWitness is violated") else {
                            throw failure(checkedTLC, message: "TLC did not confirm the candidate's actual violating outcome")
                        }
                        status = "COUNTEREXAMPLE"; lean = "COUNTEREXAMPLE_PROVED"; propertyExit = 5
                        witnessValues = candidate.serializedArguments; witnessTLC = "COUNTEREXAMPLE"
                        detail.append("The IR found a candidate; Lean proved the interpreter obligation false for this typed input and TLC reached its violating outcome.")
                    } else {
                        let hints = try PropertyProofHints.derive(property, program: snapshot.program)
                        cuts = hints.count
                        let proof = try PropertyLeanEmitter().universal(property, bound: executionBound, cuts: hints)
                        let proofURL = leanRoot.appendingPathComponent("Property\(index).lean")
                        try proof.write(to: proofURL, atomically: true, encoding: .utf8)
                        let result = try await invoke(toolchain.lean, ["-M", "2048", proofURL.path], at: leanRoot, environment: environment,
                            log: directory.appendingPathComponent("universal-lean"), timeout: timeout)
                        seconds["universalLean"] = result.elapsedSeconds
                        if result.exitCode == 0 {
                            axioms = try LeanProofAudit.check(result.standardOutput + result.standardError, allowed: toolchain.policy.allowedLeanAxioms, theoremName: "checkedProperty")
                            status = "PROVED"; lean = "PROVED"; propertyExit = 0
                        } else if resourceFailure(result.standardOutput + result.standardError) {
                            throw FormalDiagnostic(.timeout, "Universal Lean proof exhausted its computation budget")
                        } else {
                            status = "UNPROVED"; lean = "UNPROVED"; propertyExit = 6
                            detail.append("Automatic proof search did not establish the quantified theorem. This does not establish falsehood; inspect the proof and tool logs.")
                        }
                    }
                } catch {
                    propertyExit = code(error); detail.append(String(describing: error))
                }
            }
            exitCode = max(exitCode, propertyExit)
            records.append(.init(specification: property.specification, status: status, lean: lean, tla: tla, executionBound: bound,
                logicalCaseSplits: cuts, leanAxioms: axioms, counterexample: witnessValues, counterexampleTLC: witnessTLC,
                preconditionSatisfiability: "NOT_PROVED", detail: detail.joined(separator: "; "), toolSeconds: seconds))
        }
        let report = PropertyVerificationReport(schemaVersion: 1, scope: "ALL_INPUTS_UNDER_PRECONDITIONS", translation: "UNVALIDATED",
            artifactDataMatchesIR: true, artifactSHA256: snapshot.hashes, specificationSHA256: FileDigest.sha256(data), toolchain: toolchain.policy,
            timeoutSeconds: timeout, properties: records, exitCode: exitCode, runDirectory: work.path)
        let encoded = try ArtifactJSON.encode(report)
        try encoded.write(to: work.appendingPathComponent("report.json"), options: .atomic)
        return report
    }
    private func runSANY(_ name: String, at directory: URL, tools: BundledToolchain, log: URL, timeout: Double) async throws -> ToolResult {
        let result = try await invoke(tools.java, javaArguments(tools, at: directory) + ["tla2sany.SANY", name + ".tla"], at: directory, environment: tools.environment, log: log, timeout: timeout)
        let output = result.standardOutput + result.standardError
        guard result.exitCode == 0 else { throw failure(result, message: "SANY rejected the generated property specification") }
        try SANYOutputAudit.check(output, module: name)
        return result
    }
    private func invoke(_ executable: URL, _ arguments: [String], at directory: URL, environment: [String: String], log: URL, timeout: Double) async throws -> ToolResult {
        try await runner.run(executable: executable, arguments: arguments, directory: directory, environment: environment, log: log,
            timeout: timeout, maximumOutputBytes: 8_388_608, maximumWorkspaceBytes: 536_870_912)
    }
    private func javaArguments(_ tools: BundledToolchain, at directory: URL) -> [String] { ["-Djava.io.tmpdir=" + directory.appendingPathComponent("java-tmp").path, "-Xss32m", "-Xmx512m", "-cp", tools.jar.path] }
    private func resourceFailure(_ output: String) -> Bool {
        let text = output.lowercased()
        return ["stackoverflowerror", "stack overflow", "maximum memory", "excessive memory consumption", "memory limit", "maximum number of heartbeats", "maximum recursion depth", "deep recursion", "maximum number of steps", "outofmemoryerror"].contains { text.contains($0) }
    }
    private func failure(_ result: ToolResult, message: String) -> FormalDiagnostic {
        FormalDiagnostic(resourceFailure(result.standardOutput + result.standardError) ? .timeout : .toolFailure, message)
    }
    private func code(_ error: any Error) -> Int32 {
        if error is CancellationError { return 6 }
        return (error as? FormalDiagnostic)?.exitCode ?? 7
    }
}
