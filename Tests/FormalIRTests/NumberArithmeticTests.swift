import Foundation
import FormalIR
import Testing

struct NumberArithmeticTests {
    @Test(.timeLimit(.minutes(1)))
    func externalNativeVectorsAgreeWithIR() throws {
        guard let path = ProcessInfo.processInfo.environment["FORMAL_NUMBER_CASES"] else { return }
        struct Vector: Decodable {
            let op: IROperation
            let a: String
            let b: String
            let width: Int
            let result: String
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let vectors = try JSONDecoder().decode([Vector].self, from: data)
        #expect(!vectors.isEmpty)
        for vector in vectors {
            let a = try #require(UInt64(vector.a, radix: 16))
            let b = try #require(UInt64(vector.b, radix: 16))
            let expected = try #require(UInt64(vector.result, radix: vector.width == 64 ? 16 : 10))
            let left = try BitPattern(width: 64, bits: a)
            let right = try BitPattern(width: 64, bits: b)
            let actual = try BitArithmetic.evaluate(vector.op, left, right)
            let value = try BitPattern(width: vector.width, bits: expected)
            #expect(actual == .bits(value))
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func decimalParsingPreservesRoundingAndSignedZero() throws {
        let cases: [(String, UInt64)] = [("-0", 0x8000000000000000), (".5", 0x3fe0000000000000),
            ("9007199254740993", 0x4340000000000000), ("1e400", 0x7ff0000000000000),
            ("5e-324", 1), ("NaN", Binary64.canonicalNaN)]
        for (text, expected) in cases { #expect(try Binary64.parse(text) == expected) }
        for invalid in ["01", "1n", "1_000", "0x10", "1e", "garbage"] {
            #expect(throws: (any Error).self) { try Binary64.parse(invalid) }
        }
    }
    @Test(.timeLimit(.minutes(1)))
    func numericArithmeticDoesNotUseMathematicalIntegerIdentities() throws {
        let a = try Binary64.parse("0.1"); let b = try Binary64.parse("0.2")
        let sum = try Binary64.evaluate(.numberAdd, a, b)
        #expect(sum.bits == 0x3fd3333333333334)
        let maximum = try Binary64.parse("9007199254740992"); let one = try Binary64.parse("1")
        #expect(try Binary64.evaluate(.numberAdd, maximum, one).bits == maximum)
        let negative = try Binary64.parse("-5.5"); let two = try Binary64.parse("2")
        let expected = try Binary64.parse("-1.5")
        #expect(try Binary64.evaluate(.numberRemainder, negative, two).bits == expected)
    }
    @Test(.timeLimit(.minutes(1)))
    func nanAndZeroHaveTheirJavaScriptComparisonSemantics() throws {
        let nan = Binary64.canonicalNaN
        #expect(try Binary64.evaluate(.numberEqual, nan, nan).bits == 0)
        #expect(try Binary64.evaluate(.numberLessEqual, nan, 0).bits == 0)
        #expect(try Binary64.evaluate(.numberEqual, 0, 0x8000000000000000).bits == 1)
        #expect(try Binary64.evaluate(.numberSameValue, 0, 0x8000000000000000).bits == 0)
        #expect(try Binary64.evaluate(.numberSameValue, nan, nan).bits == 1)
        #expect(try Binary64.evaluate(.numberNegate, 0, 0).bits == 0x8000000000000000)
        #expect(try Binary64.evaluate(.numberTruthy, nan, nan).bits == 0)
        #expect(try Binary64.evaluate(.numberTruthy, 0x8000000000000000, 0).bits == 0)
    }
    @Test(.timeLimit(.minutes(1)))
    func numberOperatorsRejectNon64BitOperands() throws {
        let small = try BitPattern(width: 32, bits: 0)
        #expect(throws: (any Error).self) { try BitArithmetic.evaluate(.numberAdd, small, small) }
        let program = IRProgram(functions: [.init(moduleID: "M", symbol: "f", result: .bits(width: 32), blocks: [
            .init(id: "entry", parameters: [.init(id: "a", type: .bits(width: 32))], instructions: [
                .binary(destination: "r", operation: .numberAdd, left: "a", right: "a"), .returnValue("r")])])])
        #expect(throws: (any Error).self) { try program.validate() }
    }
}
