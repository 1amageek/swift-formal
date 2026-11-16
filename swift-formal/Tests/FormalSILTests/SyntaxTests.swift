import FormalCompiler
import Foundation
import Testing

struct SyntaxTests {
    @Test(.timeLimit(.minutes(1)), arguments: ["Core", "Inventory"])
    func parsesActualCanonicalCompilerOutput(name: String) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("Fixtures/SIL/\(name).sil")
        let source = try String(contentsOf: file, encoding: .utf8)
        let parsed = try CanonicalSILParser().parse(source, path: file.path)
        #expect(parsed.functions.contains { $0.hasBody && !$0.blocks.isEmpty })
        #expect(!parsed.semanticValidationPerformed)
        let opcodes = Set(parsed.functions.flatMap(\.blocks).flatMap(\.instructions).map(\.opcode))
        #expect(opcodes.contains("integer_literal"))
        if name == "Inventory" {
            #expect(opcodes.contains("begin_apply"))
            #expect(opcodes.contains("hop_to_executor"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func preservesUnknownInstructionsAndMultilineOperands() throws {
        let source = """
        sil_stage canonical
        sil @example : $@convention(thin) () -> Builtin.Int64 {
        bb0:
          %0 = integer_literal $Builtin.Int64, 7
          %1 = unknown_opcode "// not a comment", (
              %0, %0
          ) : $(Builtin.Int64, Builtin.Int64)
          return %0
        }
        """
        let result = try CanonicalSILParser().parse(source, path: "multiline.sil")
        let instructions = try #require(result.functions.first?.blocks.first?.instructions)
        #expect(instructions.count == 3)
        #expect(instructions[1].opcode == "unknown_opcode")
        #expect(instructions[1].line == 5)
        #expect(instructions[1].operands.contains { $0.text == "\"// not a comment\"" })
    }

    @Test(.timeLimit(.minutes(1)), arguments: [
        "sil_stage raw\n",
        "sil_stage canonical\n}",
        "sil_stage canonical\nsil @f : $() -> () {\nbb0:\nreturn (\n}",
        "sil_stage canonical\nsil @f : $() -> () {\nbb0:\n%0 = integer_literal $Builtin.Int1, 0\nbb0:\nreturn %0\n}",
        "sil_stage canonical\nsil @f : $() -> () {\nbb0:\nreturn \"unterminated\n}",
    ])
    func malformedInputFails(source: String) {
        #expect(throws: (any Error).self) { try CanonicalSILParser().parse(source, path: "bad.sil") }
    }

    @Test(.timeLimit(.minutes(1)))
    func tokenAndNestingLimitsFailExplicitly() {
        #expect(throws: (any Error).self) {
            try CanonicalSILParser(maximumTokens: 1).parse("sil_stage canonical", path: "large.sil")
        }
        #expect(throws: (any Error).self) {
            try CanonicalSILParser(maximumNesting: 1).parse("sil_stage canonical\nsil @f : $@convention(thin) ((Int64)) -> ()", path: "deep.sil")
        }
    }
}
