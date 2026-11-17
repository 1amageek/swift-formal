import FormalCompiler
import FormalIR
import Testing

struct NumberFrontendTests {
    private func execute(_ source: String, language: SourceLanguage, values: [String]) throws -> IRValue {
        let program = try ScalarSourceCompiler().compile(source, language: language, moduleID: "Numbers")
        let actual = try values.map { text in
            let raw = try Binary64.parse(text)
            let pattern = try BitPattern(width: 64, bits: raw)
            return IRValue.bits(pattern)
        }
        let execution = try IRInterpreter().run(program, entry: "calculate", arguments: actual)
        guard case .returned(let result) = execution.outcome else { Issue.record("Expected normal return"); throw TestFailure.failed }
        return result
    }
    private enum TestFailure: Error { case failed }

    @Test(.timeLimit(.minutes(1)), arguments: [SourceLanguage.javascript, .typescript, .bun])
    func isolatedCarriageReturnCannotEraseReturnBoundaries(_ language: SourceLanguage) throws {
        for source in ["function calculate(){return\r1;}", "function calculate(){return /*\r*/ 1;}", "function calculate(){// comment\rreturn 1;}"] {
            #expect(throws: SourceDiagnostic.self) {
                try ScalarSourceCompiler().compile(source, language: language, moduleID: "CR")
            }
        }
        for newline in ["\n", "\r\n"] {
            let source = "function calculate(a){" + newline + "return a;" + newline + "}"
            let result = try execute(source, language: language, values: ["-0"])
            #expect(result == .bits(try BitPattern(width: 64, bits: 0x8000000000000000)))
        }
    }

    @Test(.timeLimit(.minutes(1)), arguments: [SourceLanguage.bun, .typescript])
    func typedNumberAndInferredReturnUseBinary64(_ language: SourceLanguage) throws {
        let source = "function calculate(a: number, b: number) { const amount: number = a + b; return amount; }"
        let result = try execute(source, language: language, values: ["0.1", "0.2"])
        #expect(result == .bits(try BitPattern(width: 64, bits: 0x3fd3333333333334)))
    }
    @Test(.timeLimit(.minutes(1)), arguments: [SourceLanguage.bun, .javascript, .typescript])
    func untypedNumberTruthinessAndSemicolonInsertionWork(_ language: SourceLanguage) throws {
        let source = """
        function calculate(a) {
            let amount = a + .5
            if (amount) { return amount / 2 } else { return -0 }
        }
        """
        let result = try execute(source, language: language, values: ["-.5"])
        #expect(result == .bits(try BitPattern(width: 64, bits: 0x8000000000000000)))
    }
    @Test(.timeLimit(.minutes(1)))
    func inferredBooleanResultsPreserveNaNComparison() throws {
        for operation in ["<", "<=", ">", ">=", "==="] {
            let source = "function calculate(a, b) { return a \(operation) b; }"
            let result = try execute(source, language: .javascript, values: ["NaN", "0"])
            #expect(result == .bits(try BitPattern(width: 1, bits: 0)))
        }
        let result = try execute("function calculate(a) { return Number.isNaN(a); }", language: .bun, values: ["NaN"])
        #expect(result == .bits(try BitPattern(width: 1, bits: 1)))
    }
    @Test(.timeLimit(.minutes(1)))
    func inferencePropagatesBigIntAcrossCalls() throws {
        let source = "function calculate(a) { return helper(a); } function helper(b) { return b + 1n; }"
        let program = try ScalarSourceCompiler().compile(source, language: .javascript, moduleID: "BigInts")
        #expect(program.functions[0].result == .integer)
        #expect(program.functions[0].blocks[0].parameters[0].type == .integer)
        let one = try MathematicalInteger("1")
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: [.integer(one)])
        #expect(result.outcome == .returned(.integer(try MathematicalInteger("2"))))
    }
    @Test(.timeLimit(.minutes(1)))
    func logicalOperatorsShortCircuitAndPreserveSelectedValues() throws {
        let skipped = "function calculate(a){return a || recurse(a);} function recurse(a){return recurse(a);}"
        let result = try execute(skipped, language: .javascript, values: ["-1"])
        let expected = try Binary64.parse("-1")
        #expect(result == .bits(try BitPattern(width: 64, bits: expected)))
        let guardSource = "function calculate(a){return Number.isFinite(a) && a >= 0;}"
        let negative = try execute(guardSource, language: .bun, values: ["-1"])
        #expect(negative == .bits(try BitPattern(width: 1, bits: 0)))
        let positive = try execute(guardSource, language: .bun, values: [".5"])
        #expect(positive == .bits(try BitPattern(width: 1, bits: 1)))
        let fallback = try execute("function calculate(a){return a || 2;}", language: .bun, values: ["NaN"])
        #expect(fallback == .bits(try BitPattern(width: 64, bits: 0x4000000000000000)))
    }

    @Test(.timeLimit(.minutes(1)))
    func mixedDomainsAndShadowedBuiltinsAreRejected() throws {
        for source in ["function calculate(a: bigint): number { return a + 1; }", "function calculate(a) { return a + 1n + .5; }", "function calculate(Number) { return Number.isNaN(1); }", "function calculate(a) { const NaN = 0; return NaN; }"] {
            #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(source, language: .bun, moduleID: "Invalid") }
        }
    }
}
