struct ParsedSourceFunction {
    let position: SourceToken
    let range: SourceByteRange
    let name: String
    let parameters: [(String, ScalarType?)]
    let result: ScalarType?
    let body: [SourceStatement]
}
