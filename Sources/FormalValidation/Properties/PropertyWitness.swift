import FormalIR

struct PropertyWitness {
    let arguments: [IRValue]
    let outcome: IRExecutionResult.Outcome
    var serializedArguments: [String] {
        arguments.map { value in
            switch value {
            case .integer(let value): value.description
            case .bits(let bits): String(bits.bits)
            default: preconditionFailure("Nonscalar witness argument")
            }
        }
    }
}
