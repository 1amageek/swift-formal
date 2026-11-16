import FormalIR
import Testing

struct ArithmeticTests {
    @Test(.timeLimit(.minutes(1)))
    func exhaustivelyChecksFourBitArithmetic() throws {
        for a in UInt64(0)...15 {
            for b in UInt64(0)...15 {
                let left = try BitPattern(width: 4, bits: a)
                let right = try BitPattern(width: 4, bits: b)
                let signedA = a < 8 ? Int(a) : Int(a) - 16
                let signedB = b < 8 ? Int(b) : Int(b) - 16
                let cases: [(IROperation, Int, Bool)] = [
                    (.signedAddOverflow, signedA + signedB, !(-8...7).contains(signedA + signedB)),
                    (.signedSubtractOverflow, signedA - signedB, !(-8...7).contains(signedA - signedB)),
                    (.signedMultiplyOverflow, signedA * signedB, !(-8...7).contains(signedA * signedB)),
                    (.unsignedAddOverflow, Int(a + b), a + b > 15),
                    (.unsignedSubtractOverflow, Int(a) - Int(b), a < b),
                    (.unsignedMultiplyOverflow, Int(a * b), a * b > 15),
                ]
                for (operation, mathematical, overflow) in cases {
                    let value = try BitArithmetic.evaluate(operation, left, right)
                    let expectedBits = try BitPattern(width: 4, bits: UInt64((mathematical % 16 + 16) % 16))
                    let expectedFlag = try BitPattern(width: 1, bits: overflow ? 1 : 0)
                    #expect(value == .aggregate([.bits(expectedBits), .bits(expectedFlag)]))
                }
            }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func distinguishesSignedAndUnsignedEndpoints() throws {
        let minimum = try BitPattern(width: 64, bits: 1 << 63)
        let one = try BitPattern(width: 64, bits: 1)
        let signed = try BitArithmetic.evaluate(.signedSubtractOverflow, minimum, one)
        let unsigned = try BitArithmetic.evaluate(.unsignedSubtractOverflow, minimum, one)
        let maximum = try BitPattern(width: 64, bits: UInt64(Int64.max))
        let yes = try BitPattern(width: 1, bits: 1)
        let no = try BitPattern(width: 1, bits: 0)
        #expect(signed == .aggregate([.bits(maximum), .bits(yes)]))
        #expect(unsigned == .aggregate([.bits(maximum), .bits(no)]))
        #expect(throws: (any Error).self) { try BitPattern(width: 1, bits: 2) }
    }
}
