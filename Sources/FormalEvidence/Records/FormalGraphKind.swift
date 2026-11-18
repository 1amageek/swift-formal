public enum FormalGraphKind: String, Codable, Sendable {
    case tlaSpecification, tlaStateSpace, counterexample, leanDeclarations, leanProofTerm, irControlFlow
}
