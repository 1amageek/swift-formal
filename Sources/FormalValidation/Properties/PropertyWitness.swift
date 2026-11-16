import FormalIR

struct PropertyWitness {
    let arguments: [IRValue]
    let outcome: IRExecutionResult.Outcome
    let views: [ScalarView]
    init(arguments: [IRValue], outcome: IRExecutionResult.Outcome, views: [ScalarView] = []) {
        self.arguments = arguments; self.outcome = outcome; self.views = views
    }
    var serializedArguments: [String] {
        arguments.enumerated().map { index, value in
            switch value {
            case .integer(let value): value.description
            case .bits(let bits): views.indices.contains(index) && views[index] == .number ? Binary64.serialize(bits.bits) : String(bits.bits)
            default: preconditionFailure("Nonscalar witness argument")
            }
        }
    }
}
