public enum IRInstruction: Codable, Sendable, Equatable {
    case integerLiteral(destination: String, value: MathematicalInteger)
    case integerBinary(destination: String, operation: IRIntegerOperation, left: String, right: String)
    case failIf(condition: String, kind: IRFailureKind, message: String)
    case literal(destination: String, value: BitPattern)
    case aggregate(destination: String, elements: [String])
    case extract(destination: String, source: String, index: Int)
    case binary(destination: String, operation: IROperation, left: String, right: String)
    case functionRef(destination: String, symbol: String)
    case call(destination: String, callee: String, arguments: [String])
    case jump(block: String, arguments: [String])
    case branch(condition: String, thenBlock: String, thenArguments: [String], elseBlock: String, elseArguments: [String])
    case trapIf(condition: String, message: String)
    case returnValue(String)

    public var isTerminator: Bool {
        switch self {
        case .jump, .branch, .returnValue: true
        default: false
        }
    }

    public var destination: String? {
        switch self {
        case .integerLiteral(let destination, _), .integerBinary(let destination, _, _, _), .literal(let destination, _), .aggregate(let destination, _), .extract(let destination, _, _),
             .binary(let destination, _, _, _), .functionRef(let destination, _), .call(let destination, _, _): destination
        default: nil
        }
    }
}
