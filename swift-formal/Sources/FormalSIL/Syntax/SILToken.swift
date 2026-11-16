public struct SILToken: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case word
        case punctuation
        case string
        case newline
    }

    public let kind: Kind
    public let text: String
    public let line: Int
    public let column: Int
}
