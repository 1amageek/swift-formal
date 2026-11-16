import FormalIR
import FormalLowering
import FormalSIL
import Foundation
import Testing

struct ScalarTests {
    private func fixture() throws -> SILModuleSyntax {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fixtures/SIL/Core.sil"), encoding: .utf8)
        return try CanonicalSILParser().parse(source, path: "Core.sil")
    }

    private func integer(_ bits: UInt64) throws -> IRValue {
        let value = try BitPattern(width: 64, bits: bits)
        return .aggregate([.bits(value)])
    }

    @Test(.timeLimit(.minutes(1)))
    func actualSILSubtractionBranchesAndCalls() throws {
        let input = try fixture()
        let a = try integer(9)
        let b = try integer(2)
        let expected = try integer(7)
        for symbol in ["$s4Core8subtractys5Int64VAD_ADtF", "$s4Core4callys5Int64VAD_ADtF"] {
            let result = try ScalarSILLowering().lower(input, moduleID: "Core", entries: [symbol])
            #expect(!result.independentlyValidated)
            #expect(!result.rules.isEmpty)
            let execution = try IRInterpreter().run(result.program, entry: symbol, arguments: [a, b])
            #expect(execution.outcome == .returned(expected))
        }
        let negative = try integer(UInt64(bitPattern: -7))
        let positive = try integer(7)
        let symbol = "$s4Core6chooseys5Int64VADF"
        let result = try ScalarSILLowering().lower(input, moduleID: "Core", entries: [symbol])
        let execution = try IRInterpreter().run(result.program, entry: symbol, arguments: [negative])
        #expect(execution.outcome == .returned(positive))
    }

    @Test(.timeLimit(.minutes(1)))
    func actualSILDifferentiatesTrapAndWrap() throws {
        let input = try fixture()
        let minimum = try integer(1 << 63)
        let one = try integer(1)
        let checked = "$s4Core8subtractys5Int64VAD_ADtF"
        let wrapping = "$s4Core16wrappingSubtractys5Int64VAD_ADtF"
        let checkedIR = try ScalarSILLowering().lower(input, moduleID: "Core", entries: [checked])
        let checkedExecution = try IRInterpreter().run(checkedIR.program, entry: checked, arguments: [minimum, one])
        #expect(checkedExecution.outcome == .trapped("arithmetic overflow"))
        let wrappingIR = try ScalarSILLowering().lower(input, moduleID: "Core", entries: [wrapping])
        let wrapped = try IRInterpreter().run(wrappingIR.program, entry: wrapping, arguments: [minimum, one])
        let maximum = try integer(UInt64(Int64.max))
        #expect(wrapped.outcome == .returned(maximum))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsReachableMemoryAndMissingCallee() throws {
        let input = try fixture()
        #expect(throws: (any Error).self) {
            try ScalarSILLowering().lower(input, moduleID: "Core", entries: ["$s4Core4loopys5Int64VADF"])
        }
        #expect(throws: (any Error).self) {
            try ScalarSILLowering().lower(input, moduleID: "Core", entries: ["$sMissing"])
        }
    }
    @Test(.timeLimit(.minutes(1)), arguments: ["257", "-129"])
    func rejectsOutOfRangeLiterals(text: String) throws {
        let source = "sil_stage canonical\nsil @entry : $@convention(thin) () -> Builtin.Int8 {\nbb0:\n%0 = integer_literal $Builtin.Int8, \(text)\nreturn %0\n}"
        let syntax = try CanonicalSILParser().parse(source, path: "invalid.sil")
        #expect(throws: (any Error).self) {
            try ScalarSILLowering().lower(syntax, moduleID: "Test", entries: ["entry"])
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesEscapedTrapMessages() throws {
        let source = #"""
        sil_stage canonical
        sil @entry : $@convention(thin) () -> Builtin.Int1 {
        bb0:
          %0 = integer_literal $Builtin.Int1, -1
          cond_fail %0, "quoted \"message\""
          return %0
        }
        """#
        let syntax = try CanonicalSILParser().parse(source, path: "quoted.sil")
        let lowered = try ScalarSILLowering().lower(syntax, moduleID: "Test", entries: ["entry"])
        let result = try IRInterpreter().run(lowered.program, entry: "entry", arguments: [])
        #expect(result.outcome == .trapped("quoted \"message\""))
    }

}
