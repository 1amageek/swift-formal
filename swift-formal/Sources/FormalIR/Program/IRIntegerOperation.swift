public enum IRIntegerOperation: String, Codable, Sendable, CaseIterable {
    case add, subtract, multiply, lessThan, equal
    public var isComparison: Bool { self == .lessThan || self == .equal }
}
