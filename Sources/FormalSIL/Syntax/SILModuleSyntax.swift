public struct SILModuleSyntax: Sendable, Equatable {
    public struct Instruction: Sendable, Equatable {
        public let results: [String]
        public let opcode: String
        public let operands: [SILToken]
        public let line: Int
    }

    public struct Block: Sendable, Equatable {
        public let id: String
        public let arguments: [SILToken]
        public let instructions: [Instruction]
    }

    public struct Function: Sendable, Equatable {
        public let symbol: String
        public let header: [SILToken]
        public let blocks: [Block]
        public let hasBody: Bool
        public let line: Int
    }

    public let path: String
    public let functions: [Function]
    public let declarations: [[SILToken]]
    public let semanticValidationPerformed: Bool
}
