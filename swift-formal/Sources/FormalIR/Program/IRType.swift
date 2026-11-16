public indirect enum IRType: Codable, Sendable, Equatable {
    case bits(width: Int)
    case aggregate([IRType])
    case function(parameters: [IRType], result: IRType)

    public func isValid() -> Bool { isValid(depth: 0) }

    private func isValid(depth: Int) -> Bool {
        guard depth < 128 else { return false }
        switch self {
        case .bits(let width): return (1...64).contains(width)
        case .aggregate(let elements): return elements.allSatisfy { $0.isValid(depth: depth + 1) }
        case .function(let parameters, let result):
            return parameters.allSatisfy { $0.isValid(depth: depth + 1) } && result.isValid(depth: depth + 1)
        }
    }
}
