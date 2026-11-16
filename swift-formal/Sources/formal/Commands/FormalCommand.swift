import FormalCore
import FormalCompiler
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
            return CommandResult(standardOutput: "formal 0.1.0-bootstrap\n")
        case "profiles":
            guard arguments.count == 1 else { throw invalidArguments() }
            return try json(SourceLanguage.allCases.map { ["language": $0.rawValue, "profile": $0.profile, "status": "DRAFT_UNVALIDATED", "assumptions": $0.assumptions.joined(separator: "; ")] })
        case "translate":
            guard arguments.last == "--draft-unvalidated" else { throw invalidArguments() }
            let values = try options(Array(arguments.dropFirst().dropLast()), required: ["--language", "--source", "--output"])
            guard let language = SourceLanguage(rawValue: values["--language"]!) else { throw invalidArguments() }
            let report = try DraftTranslation().perform(source: values["--source"]!, language: language, output: values["--output"]!)
            return try json(report)
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
        case "capture", "generate", "validate", "check", "coverage", "replay":
            // FIXME(INCOMPLETE_IMPLEMENTATION): The bootstrap CLI routes these public commands here.
            // Strict SIL capture/generation, full semantics, and independent validation remain incomplete.
            // Do not return success until the corresponding specification acceptance tests pass.
            throw FormalDiagnostic(.unsupportedOperation, "\(command) is not implemented in this bootstrap package; no artifacts or verification results were produced.")
        default:
            throw FormalDiagnostic(.invalidArguments, "Unknown command: \(command)")
        }
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
    formal 0.1.0-bootstrap
    Usage:
      formal profiles
      formal translate --language <name> --source <file> --output <new-directory> --draft-unvalidated
      formal doctor --toolchain-lock <path>
      formal inspect-bundle --bundle <path> --toolchain-lock <path>
      formal --version
      formal --help

    capture, generate, validate, check, coverage, replay: not implemented (exit 3).
    Bundle inspection checks metadata and hashes, not SIL semantics.
    translate emits experimental TLA+ and Lean for scalar-v1 source profiles.
    Draft output is UNVALIDATED; independent semantic validation and property proof are unavailable.

    """
}
