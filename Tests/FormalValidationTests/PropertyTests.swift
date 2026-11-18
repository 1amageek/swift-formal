import Foundation
import FormalCore
import FormalIR
import FormalCompiler
@testable import FormalValidation
import Testing

struct PropertyTests {
    private func specification(pre: String = "true", post: String = "result == arg0", views: [String] = ["integer"], result: String = "integer") throws -> PropertySpecification {
        let object: [String: Any] = ["schemaVersion": 1, "properties": [["name": "identity", "entry": "calculate", "inputViews": views, "resultView": result, "requires": pre, "ensures": post]]]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try PropertySpecification.decode(data)
    }
    private func compile(_ source: String, language: SourceLanguage = .python) throws -> IRProgram {
        try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((source).utf8), language: language, moduleID: "Source")).program
    }

    @Test(.timeLimit(.minutes(1)))
    func parsesTypedLogicAndEvaluatesPrecedence() throws {
        let expression = try PropertyExpressionParser.parse("arg0 < 0 || arg1 > 0 && !(result == 0)", inputs: [.integer, .integer], result: .integer)
        let zero = PropertyScalar.integer(try MathematicalInteger("0"))
        let positive = PropertyScalar.integer(try MathematicalInteger("1"))
        let negative = PropertyScalar.integer(try MathematicalInteger("-1"))
        let a = try expression.evaluate(arguments: [zero, positive], result: zero)
        let b = try expression.evaluate(arguments: [negative, zero], result: zero)
        let c = try expression.evaluate(arguments: [zero, positive], result: negative)
        #expect(try !a.boolean)
        #expect(try b.boolean)
        #expect(try c.boolean)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsCodeInjectionUnknownFieldsAndTypeErrors() throws {
        for expression in ["by sorry", "True", "arg0; import Lean", "arg00 == 0", "arg1 == 0", "result", "arg0 && true", "result == true", "arg0 / 1 == 0", "arg0 == 0 -- ignored", "arg0 < result < 2"] {
            #expect(throws: (any Error).self) { try specification(post: expression) }
        }
        #expect(throws: (any Error).self) { try specification(pre: "result > 0") }
        let valid = try specification()
        let encoded = try JSONEncoder().encode(valid)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        object["ignored"] = true
        let changed = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: (any Error).self) { try PropertySpecification.decode(changed) }
    }

    @Test(.timeLimit(.minutes(1)))
    func boundsParserRecursionAndActualTreeDepth() throws {
        let atLimit = "result == arg0" + String(repeating: " + 0", count: 62)
        _ = try specification(post: atLimit)
        #expect(throws: (any Error).self) { try specification(post: atLimit + " + 0") }
        let nested = String(repeating: "(", count: 65) + "true" + String(repeating: ")", count: 65)
        #expect(throws: (any Error).self) { try specification(post: nested) }
        #expect(throws: (any Error).self) { try specification(post: "result == " + String(repeating: "1", count: 257)) }
    }

    @Test(.timeLimit(.minutes(1)))
    func interpretationsMustMatchActualEntrySignature() throws {
        let program = try compile("func calculate(_ a: Int64) -> Int64 { return a }", language: .swift)
        for view in ["signed", "unsigned"] {
            let spec = try specification(views: [view], result: view)
            _ = try BoundProperty(spec.properties[0], program: program)
        }
        for view in ["integer", "boolean"] {
            let spec = try specification(views: [view], result: view)
            #expect(throws: (any Error).self) { try BoundProperty(spec.properties[0], program: program) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func executionBoundCoversBranchesAndCallsAndRejectsCycles() throws {
        let source = """
        def helper(a: int) -> int:
            return a + 1
        def calculate(a: int, b: int) -> int:
            if a < b:
                return helper(a)
            else:
                return helper(b)
        """
        let program = try compile(source)
        let bound = try PropertyExecutionBound.derive(program, entry: "calculate")
        for values in [["1", "2"], ["2", "1"]] {
            let arguments = try values.map { IRValue.integer(try MathematicalInteger($0)) }
            let observed = try IRInterpreter(fuel: bound).run(program, entry: "calculate", arguments: arguments)
            #expect(observed.steps < bound)
            #expect(observed.outcome == .returned(.integer(try MathematicalInteger("2"))))
        }
        let recursive = try compile("def calculate(a: int) -> int:\n    return calculate(a)\n")
        #expect(throws: (any Error).self) { try PropertyExecutionBound.derive(recursive, entry: "calculate") }
        let loop = IRProgram(functions: [.init(moduleID: "M", symbol: "calculate", result: .integer, blocks: [
            .init(id: "entry", parameters: [.init(id: "a", type: .integer)], instructions: [.jump(block: "entry", arguments: ["a"])])])])
        try loop.validate()
        #expect(throws: (any Error).self) { try PropertyExecutionBound.derive(loop, entry: "calculate") }
    }

    @Test(.timeLimit(.minutes(1)))
    func findsTheSignedOverflowBoundaryAsACandidate() throws {
        let program = try compile("func calculate(_ a: Int64) -> Int64 { return a + 1 }", language: .swift)
        let specification = try specification(post: "result > arg0", views: ["signed"], result: "signed")
        let property = try BoundProperty(specification.properties[0], program: program)
        let bound = try PropertyExecutionBound.derive(program, entry: "calculate")
        let found = try PropertyWitnessSearch().find(property, program: program, bound: bound)
        let candidate = try #require(found)
        guard case .bits(let bits) = candidate.arguments[0] else { Issue.record("Expected bit witness"); return }
        #expect(bits.signedValue == Int64.max)
        guard case .trapped = candidate.outcome else { Issue.record("Expected an overflow trap"); return }
    }

    @Test(.timeLimit(.minutes(1)))
    func candidateSearchUsesLargePropertyConstants() throws {
        let constant = "10000000000000000000000000000000000000001"
        let program = try compile("def calculate(a: int) -> int:\n    return a\n")
        let specification = try specification(post: "result != " + constant)
        let property = try BoundProperty(specification.properties[0], program: program)
        let bound = try PropertyExecutionBound.derive(program, entry: "calculate")
        let found = try PropertyWitnessSearch().find(property, program: program, bound: bound)
        let candidate = try #require(found)
        #expect(candidate.serializedArguments == [constant])
    }

    @Test(.timeLimit(.minutes(1)))
    func universalAxiomAuditRejectsNativeTrustAndAdmissions() throws {
        let allowed = ["propext", "Classical.choice", "Quot.sound"]
        _ = try LeanProofAudit.check("'checkedProperty' depends on axioms: [propext, Classical.choice, Quot.sound]", allowed: allowed, theoremName: "checkedProperty")
        for name in ["sorryAx", "Lean.trustCompiler", "Lean.ofReduceBool", "custom"] {
            #expect(throws: (any Error).self) { try LeanProofAudit.check("'checkedProperty' depends on axioms: [\(name)]", allowed: allowed, theoremName: "checkedProperty") }
        }
    }
}
