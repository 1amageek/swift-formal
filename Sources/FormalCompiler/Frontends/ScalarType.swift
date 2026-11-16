import FormalIR

enum ScalarType: Equatable {
    case signed, signed32, unsigned, integer, boolean, number
    var ir: IRType {
        switch self {
        case .signed, .unsigned, .number: .bits(width: 64)
        case .signed32: .bits(width: 32)
        case .integer: .integer
        case .boolean: .bits(width: 1)
        }
    }
}
