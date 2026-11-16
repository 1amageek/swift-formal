import Foundation
import FormalCore

/// ECMAScript binary64 values, represented by exact bits with canonical NaNs.
public enum Binary64 {
    public static let canonicalNaN: UInt64 = 0x7ff8000000000000
    public static func canonical(_ bits: UInt64) -> UInt64 {
        bits & 0x7fffffffffffffff > 0x7ff0000000000000 ? canonicalNaN : bits
    }
    public static func parse(_ text: String) throws -> UInt64 {
        guard text.utf8.count <= 256 else { throw invalid("Number literal exceeds 256 bytes") }
        if text.hasPrefix("bits:"), text.count == 21, let raw = UInt64(text.dropFirst(5), radix: 16) { return canonical(raw) }
        if text == "NaN" { return canonicalNaN }
        if text == "Infinity" { return 0x7ff0000000000000 }
        if text == "-Infinity" { return 0xfff0000000000000 }
        let grammar = "^-?(?:(?:0|[1-9][0-9]*)(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"
        guard text.range(of: grammar, options: .regularExpression) != nil, let value = Double(text) else { throw invalid("Invalid Number literal") }
        return canonical(value.bitPattern)
    }
    public static func serialize(_ bits: UInt64) -> String { "bits:" + String(format: "%016llx", canonical(bits)) }
    public static func evaluate(_ operation: IROperation, _ left: UInt64, _ right: UInt64) throws -> (bits: UInt64, boolean: Bool) {
        let a = Double(bitPattern: left); let b = Double(bitPattern: right)
        let result: Double
        let flag: Bool
        switch operation {
        case .numberAdd: result = a + b
        case .numberSubtract: result = a - b
        case .numberMultiply: result = a * b
        case .numberDivide: result = a / b
        case .numberRemainder: result = a.truncatingRemainder(dividingBy: b)
        case .numberNegate: return (canonical(left ^ 0x8000000000000000), false)
        case .numberAbsolute: return (canonical(left & 0x7fffffffffffffff), false)
        case .numberEqual: flag = a == b; return (flag ? 1 : 0, true)
        case .numberLessThan: flag = a < b; return (flag ? 1 : 0, true)
        case .numberLessEqual: flag = a <= b; return (flag ? 1 : 0, true)
        case .numberSameValue: flag = (a.isNaN && b.isNaN) || canonical(left) == canonical(right); return (flag ? 1 : 0, true)
        case .numberIsNaN: return (a.isNaN ? 1 : 0, true)
        case .numberIsFinite: return (a.isFinite ? 1 : 0, true)
        case .numberIsInteger: flag = a.isFinite && a.rounded(.towardZero) == a; return (flag ? 1 : 0, true)
        case .numberIsSafeInteger: flag = a.isFinite && a.rounded(.towardZero) == a && abs(a) <= 9007199254740991; return (flag ? 1 : 0, true)
        case .numberTruthy: return (!a.isNaN && a != 0 ? 1 : 0, true)
        default: throw invalid("Not a Number operation")
        }
        return (canonical(result.bitPattern), false)
    }
    private static func invalid(_ text: String) -> FormalDiagnostic { .init(.invalidManifest, text) }
}
