public struct SourceDiagnostic: Error, Sendable, CustomStringConvertible {
    public let language: SourceLanguage
    public let line: Int
    public let column: Int
    public let message: String
    public var description: String { "\(language.rawValue):\(line):\(column): \(message)" }
}
