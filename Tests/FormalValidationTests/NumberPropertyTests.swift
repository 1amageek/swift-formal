import Foundation
import FormalCore
import FormalIR
@testable import FormalValidation
import Testing

struct NumberPropertyTests {
    @Test(.timeLimit(.minutes(1)))
    func propertyNumberEqualityIsNotStructuralEquality() throws {
        let expression = try PropertyExpressionParser.parse("arg0 == arg0", inputs: [.number], result: nil)
        let value = try expression.evaluate(arguments: [.number(Binary64.canonicalNaN)], result: nil)
        #expect(try !value.boolean)
        let same = try PropertyExpressionParser.parse("sameValue(arg0, arg0)", inputs: [.number], result: nil)
        let sameResult = try same.evaluate(arguments: [.number(Binary64.canonicalNaN)], result: nil)
        #expect(try sameResult.boolean)
    }
    @Test(.timeLimit(.minutes(1)))
    func decimalExpressionsUseNumberRoundingAndNegativeZero() throws {
        let expression = try PropertyExpressionParser.parse("0.1 + 0.2 == 0.3", inputs: [], result: .number)
        let evaluated = try expression.evaluate(arguments: [], result: nil)
        #expect(try !evaluated.boolean)
        let zero = try PropertyExpressionParser.parse("isNegativeZero(-0) && !sameValue(-0, 0)", inputs: [], result: .number)
        let checked = try zero.evaluate(arguments: [], result: nil)
        #expect(try checked.boolean)
    }
    @Test(.timeLimit(.minutes(1)))
    func scenariosParseExactBitsWithExplicitNumberViews() throws {
        let object: [String: Any] = ["schemaVersion": 1, "fuel": 8, "cases": [["name": "zero", "entry": "f", "arguments": ["-0"], "inputViews": ["number"], "resultView": "number", "expected": ["status": "returned", "value": "bits:8000000000000000"]]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        let specification = try VerificationScenario.decode(data)
        let program = IRProgram(functions: [.init(moduleID: "M", symbol: "f", result: .bits(width: 64), blocks: [.init(id: "entry", parameters: [.init(id: "a", type: .bits(width: 64))], instructions: [.returnValue("a")])])])
        let item = try ScalarCase(specification.cases[0], program: program)
        #expect(item.matches(.returned(.bits(try BitPattern(width: 64, bits: 0x8000000000000000)))))
        #expect(!item.matches(.returned(.bits(try BitPattern(width: 64, bits: 0)))))
        #expect(throws: (any Error).self) { try ScalarCase.value(".1", type: .bits(width: 32), view: .number) }
    }
}
