import FormalCore

/// An immutable arbitrary precision integer, serialized as a canonical decimal string.
public struct MathematicalInteger: Sendable, Equatable, Comparable, Codable, CustomStringConvertible {
    public let negative: Bool
    private let digits: [UInt8] // Least significant decimal digit first; zero has no digits.
    public var digitCount: Int { max(1, digits.count) }
    public var description: String {
        (negative ? "-" : "") + (digits.isEmpty ? "0" : String(decoding: digits.reversed().map { $0 + 48 }, as: UTF8.self))
    }

    public init(_ decimal: String, maximumDigits: Int = 100_000) throws {
        let bytes = Array(decimal.utf8)
        let sign = bytes.first == 45
        let raw = sign ? Array(bytes.dropFirst()) : bytes
        guard !raw.isEmpty, raw.count <= maximumDigits, raw.allSatisfy({ (48...57).contains($0) }),
              raw.count == 1 || raw.first != 48, !(sign && raw == [48]) else {
            throw FormalDiagnostic(.invalidManifest, "Invalid or oversized canonical integer")
        }
        self.init(negative: sign, digits: raw == [48] ? [] : raw.reversed().map { $0 - 48 })
    }
    private init(negative: Bool, digits: [UInt8]) {
        var canonical = digits
        while canonical.last == 0 { canonical.removeLast() }
        self.digits = canonical
        self.negative = !canonical.isEmpty && negative
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decimal = try container.decode(String.self)
        try self.init(decimal)
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
    public static func < (a: Self, b: Self) -> Bool {
        if a.negative != b.negative { return a.negative }
        let comparison = magnitudeLess(a.digits, b.digits)
        return a.negative ? a.digits != b.digits && !comparison : comparison
    }
    private static func magnitudeLess(_ a: [UInt8], _ b: [UInt8]) -> Bool {
        if a.count != b.count { return a.count < b.count }
        return a.reversed().lexicographicallyPrecedes(b.reversed())
    }
    public func negated() -> Self { Self(negative: !negative, digits: digits) }
    public func adding(_ other: Self) -> Self {
        if negative == other.negative {
            var result: [UInt8] = []; var carry = 0
            for i in 0..<max(digits.count, other.digits.count) {
                let sum = (i < digits.count ? Int(digits[i]) : 0) + (i < other.digits.count ? Int(other.digits[i]) : 0) + carry
                result.append(UInt8(sum % 10)); carry = sum / 10
            }
            if carry != 0 { result.append(UInt8(carry)) }
            return Self(negative: negative, digits: result)
        }
        let smaller = Self.magnitudeLess(digits, other.digits)
        let a = smaller ? other : self; let b = smaller ? self : other
        var result: [UInt8] = []; var borrow = 0
        for i in a.digits.indices {
            var difference = Int(a.digits[i]) - (i < b.digits.count ? Int(b.digits[i]) : 0) - borrow
            borrow = difference < 0 ? 1 : 0
            if difference < 0 { difference += 10 }
            result.append(UInt8(difference))
        }
        return Self(negative: a.negative, digits: result)
    }
    public func multiplied(by other: Self) -> Self {
        if digits.isEmpty || other.digits.isEmpty { return Self(negative: false, digits: []) }
        var result = [UInt8](repeating: 0, count: digits.count + other.digits.count)
        for i in digits.indices {
            var carry = 0
            for j in other.digits.indices {
                let value = Int(result[i+j]) + Int(digits[i]) * Int(other.digits[j]) + carry
                result[i+j] = UInt8(value % 10); carry = value / 10
            }
            result[i + other.digits.count] = UInt8(carry)
        }
        return Self(negative: negative != other.negative, digits: result)
    }
}
