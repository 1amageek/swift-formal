import FormalIR

enum ScalarType: Equatable {
    case signed, unsigned, integer, boolean
    var ir: IRType {
        switch self {
        case .signed, .unsigned: .bits(width: 64)
        case .integer: .integer
        case .boolean: .bits(width: 1)
        }
    }
}
