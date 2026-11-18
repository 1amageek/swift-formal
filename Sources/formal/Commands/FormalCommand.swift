import FormalCore
import FormalCompiler
import FormalValidation
import Foundation

public struct FormalCommand: Sendable {
    private let compiler: any CompilerProbing
    private let bundles: any BundleInspecting

    public init(
        compiler: any CompilerProbing = LocalCompilerProbe(),
        bundles: any BundleInspecting = BundleInspector()
    ) {
        self.compiler = compiler
        self.bundles = bundles
    }

    public func run(arguments: [String]) async -> CommandResult {
        do { return try await execute(arguments) }
        catch is CancellationError { return failure(FormalDiagnostic(.interrupted, "Operation cancelled")) }
        catch let source as SourceDiagnostic {
            return failure(FormalDiagnostic(.sourceParseFailed, source.description))
        }
        catch let diagnostic as FormalDiagnostic {
            return failure(diagnostic)
        } catch {
            return failure(FormalDiagnostic(.ioFailure, "Operation failed: \(error)"))
        }
    }

    private func execute(_ arguments: [String]) async throws -> CommandResult {
        guard let command = arguments.first else { return CommandResult(standardOutput: Self.help) }
        switch command {
        case "--help", "-h", "help":
            guard arguments.count == 1 else { throw invalidArguments() }
            return CommandResult(standardOutput: Self.help)
        case "--version":
            guard arguments.count == 1 else { throw invalidArguments() }
            return CommandResult(standardOutput: "formal 0.4.0\n")
        case "profiles":
            guard arguments.count == 1 else { throw invalidArguments() }
            return try json(SourceLanguage.allCases.map { ["language": $0.rawValue, "profile": $0.profile, "status": "DRAFT_UNVALIDATED", "assumptions": $0.assumptions.joined(separator: "; ")] })
        case "translate":
            guard arguments.last == "--draft-unvalidated" else { throw invalidArguments() }
            let values = try flexibleOptions(Array(arguments.dropFirst().dropLast()), required: ["--language", "--source", "--output"], optional: ["--default-numeric"])
            guard let language = SourceLanguage(rawValue: values["--language"]!) else { throw invalidArguments() }
            let numeric = try numericDefault(values, language: language)
            let report = try await DraftTranslation(defaultNumeric: numeric).perform(source: values["--source"]!, language: language, output: values["--output"]!)
            return try json(report)
        case "package":
            let values = try flexibleOptions(Array(arguments.dropFirst()), required: ["--output"], optional: ["--cache"])
            try await PortableDistribution().package(output: URL(fileURLWithPath: values["--output"]!), cache: values["--cache"].map { URL(fileURLWithPath: $0) })
            return try json(["status": "PACKAGED", "directory": values["--output"]!])
        case "install":
            let values = try flexibleOptions(Array(arguments.dropFirst()), required: ["--prefix"], optional: ["--cache"])
            let binary = try await PortableDistribution().install(prefix: URL(fileURLWithPath: values["--prefix"]!), cache: values["--cache"].map { URL(fileURLWithPath: $0) })
            return try json(["status": "INSTALLED", "executable": binary.path])
        case "toolchain":
            guard arguments.count == 1 else { throw invalidArguments() }
            let tools = try PinnedToolchain().verify(at: try PortableDistribution().toolsURL)
            return try json(tools.policy)
        case "check":
            guard !(arguments.contains("--properties") && arguments.contains("--scenario")) else { throw invalidArguments() }
            let specificationOption = arguments.contains("--properties") ? "--properties" : "--scenario"
            let base: Set<String> = arguments.contains("--artifact") ? ["--artifact"] : ["--language", "--source", "--output"]
            let values = try flexibleOptions(Array(arguments.dropFirst()), required: base.union([specificationOption]), optional: ["--timeout", "--default-numeric"])
            let timeout: Double
            if let text = values["--timeout"] {
                guard let value = Double(text), value.isFinite, (1...3600).contains(value) else { throw invalidArguments() }
                timeout = value
            } else { timeout = 120 }
            let specificationURL = URL(fileURLWithPath: values[specificationOption]!)
            if specificationOption == "--properties" { _ = try PropertySpecification.load(specificationURL) }
            else { _ = try VerificationScenario.load(specificationURL) }
            let tools = try PinnedToolchain().verify(at: try PortableDistribution().toolsURL)
            let artifact: URL
            if let path = values["--artifact"] {
                guard values["--default-numeric"] == nil else { throw invalidArguments() }
                artifact = URL(fileURLWithPath: path)
            }
            else {
                guard let language = SourceLanguage(rawValue: values["--language"]!) else { throw invalidArguments() }
                let numeric = try numericDefault(values, language: language)
                _ = try await DraftTranslation(defaultNumeric: numeric).perform(source: values["--source"]!, language: language, output: values["--output"]!)
                artifact = URL(fileURLWithPath: values["--output"]!)
            }
            if specificationOption == "--properties" {
                let report = try await PropertyVerifier().check(artifact: artifact, properties: specificationURL, output: artifact.appendingPathComponent("verification/" + UUID().uuidString), evidenceBudget: CompilationPolicy.budget, toolchain: tools, timeout: timeout)
                let data = try ArtifactJSON.encode(report)
                return CommandResult(exitCode: report.exitCode, standardOutput: String(decoding: data, as: UTF8.self))
            }
            let report = try await ModelVerifier().check(artifact: artifact, scenario: specificationURL, output: artifact.appendingPathComponent("verification/" + UUID().uuidString), evidenceBudget: CompilationPolicy.budget, toolchain: tools, timeout: timeout)
            let data = try ArtifactJSON.encode(report)
            return CommandResult(exitCode: report.exitCode, standardOutput: String(decoding: data, as: UTF8.self))
        case "doctor":
            let options = try options(Array(arguments.dropFirst()), required: ["--toolchain-lock"])
            let lock = try loadLock(options["--toolchain-lock"]!)
            let identity = try await compiler.probe()
            let report = try DoctorReport(lock: lock, compiler: identity)
            return try json(report)
        case "inspect-bundle":
            let options = try options(Array(arguments.dropFirst()), required: ["--bundle", "--toolchain-lock"])
            let lock = try loadLock(options["--toolchain-lock"]!)
            let root = URL(fileURLWithPath: options["--bundle"]!)
            let report = try bundles.inspect(at: root, expectedLock: lock)
            return try json(report)
        case "capture", "generate", "validate", "coverage", "replay":
            // FIXME(INCOMPLETE_IMPLEMENTATION): The bootstrap CLI routes these public commands here.
            // Strict SIL capture/generation, full semantics, and independent validation remain incomplete.
            // Do not return success until the corresponding specification acceptance tests pass.
            throw FormalDiagnostic(.unsupportedOperation, "\(command) is not implemented in this bootstrap package; no artifacts or verification results were produced.")
        default:
            throw FormalDiagnostic(.invalidArguments, "Unknown command: \(command)")
        }
    }

    private func numericDefault(_ options: [String: String], language: SourceLanguage) throws -> SourceNumericDefault {
        guard let text = options["--default-numeric"] else { return .number }
        guard language.isJavaScriptFamily, let selected = SourceNumericDefault(rawValue: text) else { throw invalidArguments() }
        return selected
    }

    private func flexibleOptions(_ arguments: [String], required: Set<String>, optional: Set<String>) throws -> [String: String] {
        guard arguments.count % 2 == 0 else { throw invalidArguments() }
        var result: [String: String] = [:]
        for offset in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[offset]; let value = arguments[offset + 1]
            guard required.union(optional).contains(key), result[key] == nil, !value.isEmpty, !value.hasPrefix("--") else { throw invalidArguments() }
            result[key] = value
        }
        guard required.isSubset(of: Set(result.keys)) else { throw invalidArguments() }
        return result
    }

    private func options(_ arguments: [String], required: Set<String>) throws -> [String: String] {
        guard arguments.count == required.count * 2 else { throw invalidArguments() }
        var result: [String: String] = [:]
        for offset in stride(from: 0, to: arguments.count, by: 2) {
            let key = arguments[offset]
            let value = arguments[offset + 1]
            guard required.contains(key), result[key] == nil, !value.isEmpty, !value.hasPrefix("--") else {
                throw invalidArguments()
            }
            result[key] = value
        }
        guard Set(result.keys) == required else { throw invalidArguments() }
        return result
    }

    private func loadLock(_ path: String) throws -> ToolchainLock {
        let lock = try ArtifactJSON.read(ToolchainLock.self, from: URL(fileURLWithPath: path))
        try lock.validate()
        return lock
    }

    private func invalidArguments() -> FormalDiagnostic {
        FormalDiagnostic(.invalidArguments, "Invalid, duplicate, or missing arguments. Run formal --help.")
    }

    private func json<Value: Encodable>(_ value: Value) throws -> CommandResult {
        let data = try ArtifactJSON.encode(value)
        return CommandResult(standardOutput: String(decoding: data, as: UTF8.self))
    }

    private func failure(_ diagnostic: FormalDiagnostic) -> CommandResult {
        do {
            let data = try ArtifactJSON.encode(diagnostic)
            return CommandResult(exitCode: diagnostic.exitCode, standardError: String(decoding: data, as: UTF8.self))
        } catch {
            return CommandResult(exitCode: 7, standardError: "IO_FAILURE: Cannot encode diagnostic: \(error)\n")
        }
    }

    private static let help = """
    formal 0.4.0
    Usage:
      formal package --output <new-directory> [--cache <directory>]
      formal install --prefix <directory> [--cache <directory>]
      formal toolchain
      formal check --language <name> --source <file> --properties <json> --output <new-directory> [--timeout <seconds>]
      formal check --artifact <directory> --properties <json> [--timeout <seconds>]
      formal check --language <name> --source <file> --scenario <json> --output <new-directory> [--timeout <seconds>]
      formal check --artifact <directory> --scenario <json> [--timeout <seconds>]
      formal profiles
      formal translate --language <name> --source <file> --output <new-directory> --draft-unvalidated
      formal doctor --toolchain-lock <path>
      formal inspect-bundle --bundle <path> --toolchain-lock <path>
      formal --version
      formal --help

    capture, generate, validate, coverage, replay: not implemented (exit 3).
    Bundle inspection checks metadata and hashes, not SIL semantics.
    translate emits experimental TLA+ and Lean for versioned scalar source profiles.
    check --properties proves quantified generated-model pre/postconditions with Lean.
    check --scenario checks finite cases with bundled TLC and Lean.
    --default-numeric number|bigint selects unconstrained JS-family scalar types during generation.
    Translation remains UNVALIDATED; general source semantic certification is unavailable.
    install/package acquire pinned tools; checking is offline and requires an installed distribution.

    """
}
