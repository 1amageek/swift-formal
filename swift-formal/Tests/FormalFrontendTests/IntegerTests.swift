import Testing
import FormalIR

struct IntegerTests {
    @Test func arbitraryPrecisionArithmetic() throws {
        let a = try MathematicalInteger("9999999999999999999999999999999999999999")
        let b = try MathematicalInteger("1")
        #expect(a.adding(b).description == "10000000000000000000000000000000000000000")
        #expect(b.adding(a.negated()).description == "-9999999999999999999999999999999999999998")
        #expect(a.multiplied(by: a).description == "99999999999999999999999999999999999999980000000000000000000000000000000000000001")
        #expect(a.negated() < b)
        #expect(a.negated() < b.negated())
        #expect(b.negated().adding(b).description == "0")
        #expect(throws: (any Error).self) { try MathematicalInteger("-0") }
    }
    @Test func matchesIndependentMachineArithmeticOnSmallDomain() throws {
        for left in -20...20 {
            let a = try MathematicalInteger(String(left))
            for right in -20...20 {
                let b = try MathematicalInteger(String(right))
                #expect(a.adding(b).description == String(left + right))
                #expect(a.multiplied(by: b).description == String(left * right))
                #expect((a < b) == (left < right))
            }
        }
    }

}
