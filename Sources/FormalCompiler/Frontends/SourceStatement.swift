struct SourceStatement {
    indirect enum Kind {
        case binding(String, ScalarType?, SourceExpression)
        case returned(SourceExpression)
        case conditional(SourceExpression, [SourceStatement], [SourceStatement])
    }
    let kind: Kind
    let range: SourceByteRange?
    func located(_ start: Int, _ end: Int) -> Self { Self(kind: kind, range: SourceByteRange(start: start, end: end)) }
    static func binding(_ name: String, _ type: ScalarType?, _ value: SourceExpression) -> Self { Self(kind: .binding(name,type,value), range: nil) }
    static func returned(_ value: SourceExpression) -> Self { Self(kind: .returned(value), range: nil) }
    static func conditional(_ value: SourceExpression, _ left: [Self], _ right: [Self]) -> Self { Self(kind: .conditional(value,left,right), range: nil) }
}
