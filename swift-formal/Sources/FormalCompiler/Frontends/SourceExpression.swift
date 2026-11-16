indirect enum SourceExpression {
    case literal(String), variable(String), call(String, [SourceExpression])
    case binary(String, SourceExpression, SourceExpression), unary(String, SourceExpression)
    var containsCall: Bool {
        switch self {
        case .call: true
        case .binary(_, let a, let b): a.containsCall || b.containsCall
        case .unary(_, let a): a.containsCall
        default: false
        }
    }
}
