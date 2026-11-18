struct SourceExpression {
    indirect enum Kind {
        case literal(String), variable(String), call(String, [SourceExpression])
        case binary(String, SourceExpression, SourceExpression), unary(String, SourceExpression)
    }
    let kind: Kind
    let range: SourceByteRange?
    func located(_ start: Int, _ end: Int) -> Self { Self(kind: kind, range: SourceByteRange(start: start, end: end)) }
    static func literal(_ text: String) -> Self { Self(kind: .literal(text), range: nil) }
    static func variable(_ text: String) -> Self { Self(kind: .variable(text), range: nil) }
    static func call(_ name: String, _ values: [Self]) -> Self { Self(kind: .call(name, values), range: nil) }
    static func binary(_ op: String, _ left: Self, _ right: Self) -> Self { Self(kind: .binary(op, left, right), range: nil) }
    static func unary(_ op: String, _ value: Self) -> Self { Self(kind: .unary(op, value), range: nil) }
    var containsCall: Bool {
        var pending = [self]
        while let expression = pending.popLast() {
            switch expression.kind {
            case .call: return true
            case .binary(_, let left, let right): pending.append(right); pending.append(left)
            case .unary(_, let value): pending.append(value)
            default: break
            }
        }
        return false
    }
}
