import FormalCore
import FormalIR

struct ScalarCase: Sendable {
    let specification: VerificationScenario.Case
    let arguments: [IRValue]
    let expected: IRValue?

    init(_ specification: VerificationScenario.Case, program: IRProgram) throws {
        guard let function = program.functions.first(where: { $0.symbol == specification.entry }),
              let block = function.blocks.first, block.parameters.count == specification.arguments.count else {
            throw VerificationScenario.invalid()
        }
        self.specification = specification
        var arguments: [IRValue] = []
        for (index, pair) in zip(specification.arguments, block.parameters).enumerated() {
            let (text, parameter) = pair
            let value = try Self.value(text, type: parameter.type, view: specification.inputViews?[index])
            arguments.append(value)
        }
        self.arguments = arguments
        if let value = specification.expected.value { self.expected = try Self.value(value, type: function.result, view: specification.resultView) }
        else { self.expected = nil }
    }

    static func value(_ text: String, type: IRType, view: ScalarView? = nil) throws -> IRValue {
        if let view {
            guard view.accepts(type) else { throw VerificationScenario.invalid() }
            if view == .number {
                let raw = try Binary64.parse(text)
                let pattern = try BitPattern(width: 64, bits: raw)
                return .bits(pattern)
            }
        }
        switch type {
        case .integer: return .integer(try MathematicalInteger(text, maximumDigits: 256))
        case .bits(let width):
            let integer: UInt64
            if width == 1 && ["true", "false"].contains(text) { integer = text == "true" ? 1 : 0 }
            else {
                let canonical = try MathematicalInteger(text, maximumDigits: 20)
                if canonical.negative {
                    guard let signed = Int64(text), width == 64 || signed >= -(Int64(1) << (width - 1)) else { throw VerificationScenario.invalid() }
                    integer = UInt64(bitPattern: signed) & (width == 64 ? .max : (UInt64(1) << width) - 1)
                } else {
                    guard let unsigned = UInt64(text) else { throw VerificationScenario.invalid() }
                    integer = unsigned
                }
            }
            return .bits(try BitPattern(width: width, bits: integer))
        default: throw FormalDiagnostic(.unsupportedType, "Scenarios currently support scalar bits and integer values")
        }
    }
    static func lean(_ value: IRValue) -> String { ScalarValueRenderer.lean(value) }
    static func tla(_ value: IRValue) -> String { ScalarValueRenderer.tla(value) }
    func matches(_ outcome: IRExecutionResult.Outcome) -> Bool {
        switch outcome {
        case .returned(let value): return specification.expected.status == "returned" && value == expected
        case .trapped: return specification.expected.status == "trapped"
        case .failed(let kind, _): return specification.expected.status == kind.rawValue
        case .boundExceeded: return false
        }
    }
    var proof: String {
        if let expected {
            return "theorem checkedCase : observe \"\(specification.entry)\" [\(arguments.map(Self.lean).joined(separator: ", "))] = some (.returned \(Self.lean(expected))) := by rfl\n#print axioms checkedCase\n"
        }
        let pattern: String
        if specification.expected.status == "trapped" { pattern = "| some (.trapped _) => true" }
        else { pattern = "| some (.failed .\(specification.expected.status) _) => true" }
        return """
        def expected : Bool :=
          match observe "\(specification.entry)" [\(arguments.map(Self.lean).joined(separator: ", "))] with
          \(pattern)
          | _ => false
        theorem checkedCase : expected = true := by rfl
        #print axioms checkedCase

        """
    }
    var model: String {
        let terminal = specification.expected.status
        let predicate = expected.map { " /\\ (state.status = \"returned\" => state.result = \(Self.tla($0)))" } ?? ""
        return """
        ---- MODULE CaseModel ----
        EXTENDS SwiftFormalRuntime
        VARIABLE state
        P == INSTANCE Program WITH EntrySymbol <- "\(specification.entry)", EntryArguments <- <<\(arguments.map(Self.tla).joined(separator: ","))>>, state <- state
        Init == P!Init
        Next == P!Next
        Expected == state.status \\in {"running", "\(terminal)"}\(predicate)
        ====

        """
    }
}
