import FormalCore
import FormalIR

indirect enum PropertyScalar: Equatable {
    case integer(MathematicalInteger)
    case number(UInt64)
    case boolean(Bool)

    init(_ value: IRValue, view: PropertyView) throws {
        switch (value, view) {
        case (.integer(let integer), .integer): self = .integer(integer)
        case (.bits(let bits), .number) where bits.width == 64: self = .number(Binary64.canonical(bits.bits))
        case (.bits(let bits), .signed): self = .integer(try MathematicalInteger(String(bits.signedValue)))
        case (.bits(let bits), .unsigned): self = .integer(try MathematicalInteger(String(bits.bits)))
        case (.bits(let bits), .boolean) where bits.width == 1: self = .boolean(bits.bits == 1)
        default: throw PropertySpecification.invalid("Observed value does not match its property view")
        }
    }
    var boolean: Bool {
        get throws {
            guard case .boolean(let value) = self else { throw PropertySpecification.invalid("Expected a Boolean expression") }
            return value
        }
    }
}
