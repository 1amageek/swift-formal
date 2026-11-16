indirect enum SourceStatement {
    case binding(String, ScalarType?, SourceExpression)
    case returned(SourceExpression)
    case conditional(SourceExpression, [SourceStatement], [SourceStatement])
}
