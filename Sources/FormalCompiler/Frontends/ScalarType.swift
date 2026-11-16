import FormalIR

enum ScalarType: Equatable {
    case signed, signed32, unsigned, integer, boolean
    var ir: IRType {
        switch self {
        case .signed, .unsigned: .bits(width: 64)
        case .signed32: .bits(width: 32)
        case .integer: .integer
        case .boolean: .bits(width: 1)
        }
    }
}
