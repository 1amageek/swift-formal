import Foundation
import FormalCore
import FormalIR

struct PropertyLeanEmitter {
    func universal(_ property: BoundProperty, bound: Int, cuts: [String]) throws -> String {
        var source = preamble(property, bound: bound)
        source += "\ntheorem checkedProperty \(property.binders) \(property.domainBinders) : obligation \(property.names.joined(separator: " ")) := by\n"
        for (index, type) in property.inputTypes.enumerated() {
            if case .bits(let width) = type, property.specification.inputViews[index] != .boolean {
                source += "  have validArg\(index) : ¬ (\(BoundProperty.powerOfTwo(width)) ≤ a\(index)) := by omega\n"
            }
        }
        source += "  unfold obligation\n  intro pre\n"
        for (index, proposition) in cuts.enumerated() { source += "  all_goals by_cases cut\(index) : \(proposition)\n" }
        // Canonicalize case hypotheses without turning negated guards into unrelated normal forms.
        source += "  all_goals try simp_all only [SwiftFormal.signed, Nat.reducePow, Int.ofNat_eq_natCast, SwiftFormal.numberNaN, SwiftFormal.numberFinite, SwiftFormal.numberAbs, ite_true, ite_false]\n  all_goals try omega\n"
        // Reduce one interpreter step at a time so unresolved guards cannot expand all later ticks.
        // Every simplification is kernel checked; the final goal remains the actual interpreter obligation.
        source += "  all_goals simp [*, \(Self.definitions)]\n"
        for _ in 0..<bound {
            source += "  all_goals try unfold SwiftFormal.evaluate\n  all_goals try simp [*, \(Self.definitions)]\n"
            guard source.utf8.count <= 1_048_576 else { throw FormalDiagnostic(.timeout, "Universal proof source exceeds 1 MiB") }
        }
        source += "  all_goals first | omega | grind\n#print axioms checkedProperty\n"
        for width in (0...64).reversed() {
            let numeral = BoundProperty.powerOfTwo(width)
            source = source.replacingOccurrences(of: "2 ^ \(width)", with: numeral)
            source = source.replacingOccurrences(of: "Int.ofNat (\(numeral))", with: "(\(numeral) : Int)")
        }
        return source
    }
    func counterexample(_ property: BoundProperty, bound: Int, witness: PropertyWitness) -> String {
        let arguments = witness.arguments
        let literals = arguments.map { value -> String in
            switch value {
            case .integer(let value): return "(\(value) : Int)"
            case .bits(let bits): return String(bits.bits)
            default: preconditionFailure("Nonscalar witness")
            }
        }
        let actual = literals.enumerated().map { index, literal in property.specification.inputViews[index] == .boolean ? (literal == "1" ? "true" : "false") : literal }
        let domains = property.inputTypes.enumerated().compactMap { index, type -> String? in
            if case .bits(let width) = type, property.specification.inputViews[index] != .boolean { return "\(literals[index]) < 2 ^ \(width)" }
            return nil
        }
        let domain = domains.isEmpty ? "True" : domains.map { "(\($0))" }.joined(separator: " ∧ ")
        let observed: String
        if case .returned(let value) = witness.outcome { observed = "some \(ScalarValueRenderer.lean(value))" }
        else { observed = "none" }
        let values = arguments.map(ScalarValueRenderer.lean).joined(separator: ", ")
        return preamble(property, bound: bound) + "\ntheorem checkedCounterexample : (\(domain)) ∧ ¬ obligation \(actual.joined(separator: " ")) := by\n  have observed : propertyResult [\(values)] = \(observed) := by rfl\n  simp only [obligation, observed] <;> decide\n#print axioms checkedCounterexample\n"
    }
    private func preamble(_ property: BoundProperty, bound: Int) -> String {
        """
        import Generated.Program
        open SwiftFormal Generated
        set_option maxRecDepth 8192
        set_option maxHeartbeats 1000000
        set_option linter.unusedSimpArgs false
        theorem formalRunning : (Status.running == Status.running) = true := by rfl
        theorem formalReturned (v : Value) : (Status.returned v == Status.running) = false := by rfl
        theorem formalTrapped (m : String) : (Status.trapped m == Status.running) = false := by rfl
        theorem formalFailed (k : FailureKind) (m : String) : (Status.failed k m == Status.running) = false := by rfl
        def observe (actual : List Value) : Option Status := do
          let start ← initial Generated.program "\(property.specification.entry)" actual
          match evaluate Generated.program \(bound) start with
          | .terminal final => some final.status
          | _ => none
        def propertyResult (actual : List Value) : Option Value :=
          match observe actual with
          | some (.returned value) => some value
          | _ => none
        def obligation \(property.binders) : Prop :=
          \(property.leanPrecondition) →
          match propertyResult [\(property.leanArguments.joined(separator: ", "))] with
          | some \(property.resultPattern) => \(property.leanPostcondition)
          | _ => False

        """
    }
    private static let definitions = "propertyResult, observe, Generated.program, SwiftFormal.initial, SwiftFormal.findFunction, SwiftFormal.bind, SwiftFormal.assign, SwiftFormal.tick, SwiftFormal.findBlock, SwiftFormal.lookup, SwiftFormal.integerBinary, SwiftFormal.binary, SwiftFormal.overflowResult, SwiftFormal.signed, SwiftFormal.arguments, SwiftFormal.flag, SwiftFormal.jump, formalRunning, formalReturned, formalTrapped, formalFailed, bne, Int.ofNat_eq_natCast, SwiftFormal.numberBinary, SwiftFormal.numberNeg, SwiftFormal.numberCanon, SwiftFormal.numberAbs, SwiftFormal.numberEq, SwiftFormal.numberLt, SwiftFormal.numberNaN, SwiftFormal.numberFinite, SwiftFormal.numberInteger, SwiftFormal.numberArithmeticBound, SwiftFormal.numberArithmeticFits, SwiftFormal.numberNegBound, SwiftFormal.numberNegFits"
}
