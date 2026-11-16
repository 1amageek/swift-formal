import Testing
import FormalCompiler
import FormalIR
import FormalValidation

struct JavaBunFrontendTests {
    private func compile(_ source: String, language: String) throws -> IRProgram {
        let selected = try #require(SourceLanguage(rawValue: language))
        return try ScalarSourceCompiler().compile(source, language: selected, moduleID: "NewProfiles")
    }
    private func bits(_ width: Int, _ raw: UInt64) throws -> IRValue {
        .bits(try BitPattern(width: width, bits: raw))
    }

    @Test(.timeLimit(.minutes(1)), arguments: [32, 64])
    func javaWidthsAndOverflowMatchTheirDeclaredType(_ width: Int) throws {
        let type = width == 32 ? "int" : "long"
        let program = try compile("public final class Calculations { public static \(type) calculate(\(type) a, \(type) b) { return a + b; } }", language: "java")
        #expect(program.functions[0].result == .bits(width: width))
        let sign = UInt64(1) << (width - 1)
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: [bits(width, sign - 1), bits(width, 1)])
        #expect(result.outcome == .returned(try bits(width, sign)))
        let lean = try #require(LeanEmitter().emit(program).first { $0.path == "lean/Generated/Program.lean" })
        let tla = try #require(TLAEmitter().emit(program).first { $0.path == "tla/Program.tla" })
        #expect(try BackendArtifactDecoder().decodeLeanProgram(lean.contents) == program)
        #expect(try BackendArtifactDecoder().decodeTLAProgram(tla.contents) == program)
    }

    @Test(.timeLimit(.minutes(1)))
    func javaCallsBranchesLocalsAndBooleansExecute() throws {
        let program = try compile("""
        class Calculations {
            private static boolean before(long a, long b) { return a < b; }
            static long calculate(long a, long b) {
                final boolean selected = before(a, b);
                if (selected) { return a; } else { return b; }
            }
        }
        """, language: "java")
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: [bits(64, 9), bits(64, 2)])
        #expect(result.outcome == .returned(try bits(64, 2)))
    }

    @Test(.timeLimit(.minutes(1)), arguments: ["2147483648", "9223372036854775808L"])
    func javaMinimumLiteralRequiresImmediateUnaryMinus(_ literal: String) throws {
        let width = literal.hasSuffix("L") ? 64 : 32
        let type = width == 64 ? "long" : "int"
        let prefix = "class Calculations { static \(type) calculate() { return "
        let suffix = "; } }"
        let program = try compile(prefix + "-" + literal + suffix, language: "java")
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: [])
        #expect(result.outcome == .returned(try bits(width, UInt64(1) << (width - 1))))
        for value in [literal, "-(" + literal + ")"] {
            #expect(throws: SourceDiagnostic.self) { try compile(prefix + value + suffix, language: "java") }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func javaRejectsWideningRatherThanChangingIntermediateArithmetic() throws {
        for body in ["static long calculate() { return 2147483647 + 1; }", "static long calculate(long a) { return a + 1; }", "static int calculate() { return 1L; }", "static long calculate(int a, long b) { return a + b; }"] {
            #expect(throws: SourceDiagnostic.self) { try compile("class Calculations { " + body + " }", language: "java") }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func bunAcceptsTypedAndUntypedBigIntsAndTypedBooleans() throws {
        for signature in ["function calculate(a, b)", "export function calculate(a: bigint, b: bigint): bigint"] {
            let program = try compile(signature + " { const value = a * b; return value + 1n; }", language: "bun")
            let value = try MathematicalInteger("10000000000000000000000000000000000000000")
            let result = try IRInterpreter().run(program, entry: "calculate", arguments: [.integer(value), .integer(try MathematicalInteger("2"))])
            #expect(result.outcome == .returned(.integer(try MathematicalInteger("20000000000000000000000000000000000000001"))))
        }
        let program = try compile("function calculate(a: boolean): boolean { return !a; }", language: "bun")
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: [bits(1, 1)])
        #expect(result.outcome == .returned(try bits(1, 0)))
    }

    @Test(.timeLimit(.minutes(1)))
    func newProfilesRejectUnsupportedSyntaxBeforeProducingAProgram() throws {
        let rejected = [
            ("java", "class ScalarFixture { static int hashCode() { return 0; } }"),
            ("java", "class ScalarFixture { static long wait(long a) { return a; } }"),
            ("java", "class strictfp { static int calculate() { return 0; } }"),
            ("java", "class record { static int calculate() { return 0; } }"),
            ("java", "class ScalarFixture { static int native(int a) { return a; } }"),
            ("java", "class Calculations { // " + "\\" + "u000a unexpected\n static int calculate() { return 0; } }"),
            ("java", "class Calculations { // comment\r static int ignored() { return 1; }\n static int calculate() { return 0; } }"),
            ("bun", "function calculate(a) { return\r a; }"),
            ("java", "static long calculate(long a) { return a; }"),
            ("java", "class Calculations { long calculate(long a) { return a; } }"),
            ("java", "class Calculations { static long field = 1L; }"),
            ("java", "class Calculations { static long calculate(long a) { return a++; } }"),
            ("java", "class Calculations { static long calculate(long a) { return --a; } }"),
            ("java", "class Calculations { static long calculate(long a) { return (long)a; } }"),
            ("bun", "function calculate(a: number): number { return a + 1n; }"),
            ("bun", "function calculate(a: bigint) { return a + 1; }"),
            ("bun", "function calculate(a) { return a++; }"),
            ("bun", "async function calculate(a) { return a; }"),
            ("bun", "function calculate(a) { return Bun.file(a); }")
        ]
        for (language, source) in rejected {
            #expect(throws: SourceDiagnostic.self) { try compile(source, language: language) }
        }
    }
}
