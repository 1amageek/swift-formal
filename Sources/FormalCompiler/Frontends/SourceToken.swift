struct SourceToken: Sendable {
    let text: String
    let line: Int
    let column: Int
    let startByte: Int
    let endByte: Int
    init(text: String, line: Int, column: Int, startByte: Int = 0, endByte: Int = 0) { self.text = text; self.line = line; self.column = column; self.startByte = startByte; self.endByte = endByte }
}
