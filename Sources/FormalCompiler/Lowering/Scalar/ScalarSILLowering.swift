import FormalCore
import FormalIR

public struct ScalarSILLowering: Sendable {
    public let maximumFunctions: Int

    public init(maximumFunctions: Int = 10_000) { self.maximumFunctions = maximumFunctions }

    // FIXME(INCOMPLETE_IMPLEMENTATION): This experimental scalar lowering erases nominal wrapper identity.
    // Direct library clients use this path; production CLI generation remains unsupported.
    // Do not certify translation until nominal types, SIL reference steps, and state/stuttering rules are checked.
    public func lower(_ module: SILModuleSyntax, moduleID: String, entries: [String]) throws -> ScalarLoweringResult {
        guard maximumFunctions > 0, !moduleID.isEmpty, !entries.isEmpty else {
            throw FormalDiagnostic(.invalidArguments, "Lowering requires explicit module and entry symbols.")
        }
        var definitions: [String: SILModuleSyntax.Function] = [:]
        for function in module.functions where function.hasBody {
            guard definitions[function.symbol] == nil else { throw failure(.silParseFailed, "Duplicate body", path: module.path) }
            definitions[function.symbol] = function
        }
        var pending = Array(entries.reversed())
        var visited = Set<String>()
        var functions: [IRFunction] = []
        var rules: [ScalarLoweringResult.RuleApplication] = []
        while let symbol = pending.popLast() {
            if visited.contains(symbol) { continue }
            guard visited.count < maximumFunctions else { throw failure(.unsupportedOperation, "Dependency closure limit exceeded", path: module.path) }
            guard let function = definitions[symbol] else { throw failure(.unsupportedExternal, "No body or runtime model for \(symbol)", path: module.path) }
            visited.insert(symbol)
            let decoder = ScalarDecoder(path: module.path)
            let lowered = try decoder.function(function, moduleID: moduleID)
            functions.append(lowered.0)
            rules.append(contentsOf: lowered.1)
            for block in lowered.0.blocks {
                for instruction in block.instructions {
                    if case .functionRef(_, let callee) = instruction { pending.append(callee) }
                }
            }
        }
        let program = IRProgram(functions: functions)
        try program.validate()
        return ScalarLoweringResult(program: program, rules: rules, independentlyValidated: false)
    }

    private func failure(_ code: FormalDiagnostic.Code, _ message: String, path: String) -> FormalDiagnostic {
        FormalDiagnostic(code, message, path: path)
    }
}
