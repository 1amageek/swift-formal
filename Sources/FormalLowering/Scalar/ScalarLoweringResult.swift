import FormalIR

public struct ScalarLoweringResult: Sendable {
    public struct RuleApplication: Codable, Sendable, Equatable {
        public let symbol: String
        public let block: String
        public let silLine: Int
        public let opcode: String
        public let ruleID: String
        public let irInstructionIndex: Int?
    }

    public let program: IRProgram
    public let rules: [RuleApplication]
    public let independentlyValidated: Bool
}
