public indirect enum IRValue: Codable, Sendable, Equatable {
    case bits(BitPattern)
    case aggregate([IRValue])
    case function(String)

    public func type(in program: IRProgram) -> IRType? { type(in: program, depth: 0) }

    private func type(in program: IRProgram, depth: Int) -> IRType? {
        guard depth < 128 else { return nil }
        switch self {
        case .bits(let value): return .bits(width: value.width)
        case .aggregate(let values):
            var types: [IRType] = []
            for value in values {
                guard let type = value.type(in: program, depth: depth + 1) else { return nil }
                types.append(type)
            }
            return .aggregate(types)
        case .function(let symbol): return program.functions.first { $0.symbol == symbol }?.type
        }
    }
}
