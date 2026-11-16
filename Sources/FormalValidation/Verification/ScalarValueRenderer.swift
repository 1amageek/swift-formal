import FormalIR

enum ScalarValueRenderer {
    static func lean(_ value: IRValue) -> String {
        switch value {
        case .bits(let bits): return "(.bits \(bits.width) \(bits.bits))"
        case .integer(let value): return "(.integer (\(value)))"
        default: preconditionFailure("Scalar case contains a nonscalar value")
        }
    }
    static func tla(_ value: IRValue) -> String {
        switch value {
        case .bits(let bits):
            let digits = (0..<bits.width).map { String((bits.bits >> $0) & 1) }.joined(separator: ",")
            return "Bits(\(bits.width),<<\(digits)>>)"
        case .integer(let value): return "ParseInteger(\"\(value)\")"
        default: preconditionFailure("Scalar case contains a nonscalar value")
        }
    }
}
