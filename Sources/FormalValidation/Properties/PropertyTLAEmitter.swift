import FormalIR

struct PropertyTLAEmitter {
    func emit(_ property: BoundProperty, witness: [IRValue]? = nil) -> String {
        let arguments = property.inputTypes.indices.map { view(property.specification.inputViews[$0], value: "inputs[\($0 + 1)]", type: property.inputTypes[$0]) }
        let result = view(property.specification.resultView, value: "state.result", type: property.function.result)
        let requires = property.precondition.tla(inputs: arguments, result: "FALSE")
        let ensures = property.postcondition.tla(inputs: arguments, result: result)
        let domains = property.inputTypes.enumerated().map { index, type in
            switch type {
            case .integer: return "D\(index) == {Integer(n, m) : n \\in BOOLEAN, m \\in Seq({0, 1})}"
            case .bits(let width): return "D\(index) == {Bits(\(width), b) : b \\in [1..\(width) -> {0, 1}]}"
            default: preconditionFailure("Nonscalar property input")
            }
        }.joined(separator: "\n")
        let domain: String
        if let witness { domain = "{<<\(witness.map(ScalarValueRenderer.tla).joined(separator: ", "))>>}" }
        else if property.inputTypes.isEmpty { domain = "{<<>>}" }
        else {
            let variables = property.inputTypes.indices.map { "a\($0)" }.joined(separator: ", ")
            let ranges = property.inputTypes.indices.map { "a\($0) \\in D\($0)" }.joined(separator: ", ")
            domain = "{<<\(variables)>> : \(ranges)}"
        }
        let resultType: String
        switch property.function.result {
        case .integer: resultType = "[kind |-> \"integer\"]"
        case .bits(let width): resultType = "[kind |-> \"bits\", width |-> \(width)]"
        default: preconditionFailure("Nonscalar property result")
        }
        return """
        ---- MODULE Universal ----
        EXTENDS SwiftFormalRuntime
        VARIABLES state, inputs
        RECURSIVE BitsToNat(_)
        BitsToNat(b) == IF Len(b) = 0 THEN 0 ELSE Head(b) + 2 * BitsToNat(Tail(b))
        MathInteger(v) == IF v.negative THEN -BitsToNat(v.magnitude) ELSE BitsToNat(v.magnitude)
        SignedBits(v) == IF BitsToNat(v.bits) < 2 ^ (v.width - 1) THEN BitsToNat(v.bits) ELSE BitsToNat(v.bits) - 2 ^ v.width
        \(domains)
        InputDomain == \(domain)
        P == INSTANCE Program WITH EntrySymbol <- "\(property.specification.entry)", EntryArguments <- <<>>, state <- state
        Requires == \(requires)
        Init == /\\ inputs \\in InputDomain
                /\\ Requires
                /\\ InputTypesMatch(P!ProgramData, "\(property.specification.entry)", inputs)
                /\\ state = Initial(P!ProgramData, "\(property.specification.entry)", inputs)
        Next == /\\ P!Next
                /\\ UNCHANGED inputs
        Postcondition == IF state.status = "returned" THEN
            IF ValueHasType(state.result, \(resultType)) THEN \(ensures) ELSE FALSE
          ELSE ~Terminal(state)
        Spec == Init /\\ [][Next]_<<state, inputs>>
        UniversalProperty == Spec => []Postcondition
        ====

        """
    }
    func witness(_ property: BoundProperty, _ witness: PropertyWitness) -> String {
        let outcome: String
        switch witness.outcome {
        case .returned(let value): outcome = "state.status = \"returned\" /\\ state.result = \(ScalarValueRenderer.tla(value))"
        case .trapped: outcome = "state.status = \"trapped\""
        case .failed(let kind, _): outcome = "state.status = \"\(kind.rawValue)\""
        case .boundExceeded: preconditionFailure("A bound is not a counterexample")
        }
        return """
        ---- MODULE Witness ----
        EXTENDS SwiftFormalRuntime
        VARIABLE state
        P == INSTANCE Program WITH EntrySymbol <- "\(property.specification.entry)", EntryArguments <- <<\(witness.arguments.map(ScalarValueRenderer.tla).joined(separator: ", "))>>, state <- state
        Init == P!Init
        Next == P!Next
        NotWitness == ~(\(outcome))
        ====

        """
    }
    private func view(_ view: PropertyView, value: String, type: IRType) -> String {
        switch view {
        case .number: value
        case .integer: "MathInteger(\(value))"
        case .unsigned: "BitsToNat(\(value).bits)"
        case .signed: "SignedBits(\(value))"
        case .boolean: "(\(value).bits = <<1>>)"
        }
    }
}
