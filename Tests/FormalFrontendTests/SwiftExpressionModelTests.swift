import Testing
@testable import FormalCompiler

struct SwiftExpressionModelTests {
    @Test func integerTrapChecksIncludeSignedOverflowAndInteriorZero() {
        func check(_ lhs: SwiftExpressionSite.Operand, _ op: SwiftExpressionSite.Operation, _ rhs: SwiftExpressionSite.Operand) -> String {
            SwiftExpressionSite(bytes: 0..<1, expression: .arithmetic(lhs, op, rhs)).localCheck
        }
        #expect(check(.count, .divide, .integer(7)) == "No arithmetic trap")
        #expect(check(.scalar, .divide, .integer(0)) == "Always traps")
        #expect(check(.integer(.min), .remainder, .integer(-1)) == "Always traps")
        #expect(check(.scalar, .divide, .scalar) == "Possible trap")
        #expect(check(.scalar, .remainder, .integer(-1)) == "Possible trap")
        #expect(check(.count, .multiply, .integer(0)) == "No arithmetic trap")
        #expect(check(.count, .add, .integer(1)) == "Possible trap")
        #expect(check(.integer(.min), .subtract, .integer(1)) == "Always traps")
    }
}
