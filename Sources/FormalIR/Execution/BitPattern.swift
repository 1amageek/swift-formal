import FormalCore

public struct BitPattern: Codable, Sendable, Equatable {
    public let width: Int
    public let bits: UInt64

    public init(width: Int, bits: UInt64) throws {
        guard (1...64).contains(width) else {
            throw FormalDiagnostic(.invalidManifest, "Bit width must be in 1...64.")
        }
        let mask = width == 64 ? UInt64.max : (UInt64(1) << width) - 1
        guard bits <= mask else {
            throw FormalDiagnostic(.invalidManifest, "Bit pattern exceeds its declared width.")
        }
        self.width = width
        self.bits = bits
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let width = try values.decode(Int.self, forKey: .width)
        let bits = try values.decode(UInt64.self, forKey: .bits)
        try self.init(width: width, bits: bits)
    }

    public var mask: UInt64 { width == 64 ? .max : (UInt64(1) << width) - 1 }
    public var signBit: UInt64 { UInt64(1) << (width - 1) }
    public var signedValue: Int64 {
        if width == 64 { return Int64(bitPattern: bits) }
        return Int64(bitPattern: bits & signBit == 0 ? bits : bits | ~mask)
    }
}
