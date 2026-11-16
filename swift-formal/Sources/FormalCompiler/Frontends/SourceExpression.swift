indirect enum SourceExpression {
    case literal(String), variable(String), call(String, [SourceExpression])
    case binary(String, SourceExpression, SourceExpression), unary(String, SourceExpression)
    var containsCall: Bool {
        var pending = [self]
        while let expression = pending.popLast() {
            switch expression {
            case .call: return true
            case .binary(_, let left, let right): pending.append(right); pending.append(left)
            case .unary(_, let value): pending.append(value)
            default: break
            }
        }
        return false
    }
}
