struct SourceFunction {
    let position: SourceToken
    let name: String
    let parameters: [(String, ScalarType)]
    let result: ScalarType
    let body: [SourceStatement]
}
