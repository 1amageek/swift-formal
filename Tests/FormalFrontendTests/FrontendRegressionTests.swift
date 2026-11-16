import Testing
import Foundation
import FormalCompiler
import FormalIR
import FormalValidation

struct FrontendRegressionTests {
    @Test(arguments: [SourceLanguage.c, .cpp, .javascript, .typescript, .go, .swift])
    func rejectsContiguousUpdateOperators(_ language: SourceLanguage) throws {
        let prefix: String
        let suffix: String
        switch language {
        case .c: prefix = "#include <stdint.h>\nint64_t f(int64_t a, int64_t b) { return "; suffix = "; }"
        case .cpp: prefix = "#include <cstdint>\nstd::int64_t f(std::int64_t a, std::int64_t b) { return "; suffix = "; }"
        case .javascript: prefix = "function f(a, b) { return "; suffix = "; }"
        case .typescript: prefix = "function f(a: bigint, b: bigint): bigint { return "; suffix = "; }"
        case .go: prefix = "package main\nfunc f(a int64, b int64) int64 { return "; suffix = " }"
        default: prefix = "func f(_ a: Int64, _ b: Int64) -> Int64 { return "; suffix = " }"
        }
        for expression in ["--a", "a--", "a---b", "++a", "a++"] {
            #expect(throws: SourceDiagnostic.self) {
                try ScalarSourceCompiler().compile(prefix + expression + suffix, language: language, moduleID: "Updates")
            }
        }
    }
    @Test func preservesGoUntypedConstantComparison() throws {
        let source = "package main\nfunc f(a int64, b int64) bool { return 9223372036854775807 + 1 < 0 }\n"
        let program = try ScalarSourceCompiler().compile(source, language: .go, moduleID: "Constants")
        let nine = try BitPattern(width: 64, bits: 9)
        let two = try BitPattern(width: 64, bits: 2)
        let result = try IRInterpreter().run(program, entry: "f", arguments: [.bits(nine), .bits(two)])
        #expect(result.outcome == .returned(.bits(try BitPattern(width: 1, bits: 0))))
    }
    @Test(arguments: [SourceLanguage.c, .cpp]) func rejectsCallsBeforeDeclaration(_ language: SourceLanguage) throws {
        let header = language == .c ? "stdint.h" : "cstdint"
        let type = language == .c ? "int64_t" : "std::int64_t"
        let source = "#include <\(header)>\n\(type) f(\(type) a, \(type) b) { return g(a, b); }\n\(type) g(\(type) a, \(type) b) { return a + b; }\n"
        #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(source, language: language, moduleID: "Visibility") }
    }
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }

    private func nestedChain(levels: Int, terms: Int) -> String {
        var expression = "a"
        for _ in 0..<levels { expression = "(" + expression + ")" + String(repeating: "+a", count: terms) }
        return "function f(a, b) { return " + expression + "; }\n"
    }
    @Test func rejectsNestedChainCounterexample() throws {
        let source = nestedChain(levels: 50, terms: 120)
        #expect(source.utf8.count < 13_000)
        #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(source, language: .javascript, moduleID: "Depth") }
    }
    @Test func enforcesTotalDepthForBinaryUnaryAndCallNodes() throws {
        let compiler = ScalarSourceCompiler(maximumNesting: 32)
        let chain = "(" + Array(repeating: "a", count: 20).joined(separator: "+") + ")"
        let second = "function f(a, b) { return " + chain + String(repeating: "+a", count: 20) + "; }"
        #expect(throws: SourceDiagnostic.self) { try compiler.compile(second, language: .javascript, moduleID: "Depth") }
        let unary = "function f(a, b) { return - - - - - - - - - - - - - " + chain + "; }"
        #expect(throws: SourceDiagnostic.self) { try compiler.compile(unary, language: .javascript, moduleID: "Depth") }
        let call = "function g(a, b) { return a; } function f(a, b) { return g(" + chain + String(repeating: "+a", count: 12) + ", b); }"
        #expect(throws: SourceDiagnostic.self) { try compiler.compile(call, language: .javascript, moduleID: "Depth") }
    }
    @Test func rejectsUnrepresentableGoConstantConversions() throws {
        let expressions = ["9223372036854775807 + 1", "a + (9223372036854775807 + 1)", "true + false"]
        for expression in expressions {
            let source = "package main\nfunc f(a int64, b int64) int64 { return " + expression + " }\n"
            #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(source, language: .go, moduleID: "Constants") }
        }
        let unsigned = "package main\nfunc f(a uint64, b uint64) bool { return a < -1 }\n"
        #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(unsigned, language: .go, moduleID: "Constants") }
        let oversized = "package main\nfunc f(a int64, b int64) bool { return " + String(repeating: "9", count: 76) + " * 10 > 0 }\n"
        #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(oversized, language: .go, moduleID: "Constants") }
    }
    @Test(arguments: [SourceLanguage.python, .rust]) func retainsRepeatedUnaryMinusGrammar(_ language: SourceLanguage) throws {
        let source = language == .python ? "def f(a: int, b: int) -> int:\n    return --a\n" : "fn f(a: i64, b: i64) -> i64 { return --a; }"
        let program = try ScalarSourceCompiler().compile(source, language: language, moduleID: "Unary")
        let nine: IRValue = language == .python ? .integer(try MathematicalInteger("9")) : .bits(try BitPattern(width: 64, bits: 9))
        let result = try IRInterpreter().run(program, entry: "f", arguments: [nine, nine])
        #expect(result.outcome == .returned(nine))
    }
    @Test(arguments: ["spaced-c", "spaced-cpp", "spaced-javascript", "spaced-typescript", "constants-go", "visible-c", "visible-cpp", "depth-javascript"])
    func positiveCounterpartsAgreeWithIR(_ name: String) throws {
        let language = try #require(SourceLanguage(rawValue: String(name.split(separator: "-").last!)))
        let source: String
        if name == "depth-javascript" { source = nestedChain(levels: 7, terms: 18).replacingOccurrences(of: "; }", with: "+a; }") }
        else { source = try String(contentsOf: root.appendingPathComponent("Fixtures/Regressions/\(name).source"), encoding: .utf8) }
        let program = try ScalarSourceCompiler().compile(source, language: language, moduleID: "Source")
        // entry, left, right, input kind, expected value, output kind
        let cases: [[String]]
        if name == "constants-go" {
            cases = [
                ["compareConstant", "9", "2", "signed", "false", "boolean"],
                ["narrowAfterFold", "9", "2", "signed", "9223372036854775807", "signed"],
                ["mixedConstant", "9", "2", "signed", "10", "signed"],
                ["mixedUnsigned", "18446744073709551615", "2", "unsigned", "0", "unsigned"],
                ["compareUnsigned", "0", "2", "unsigned", "true", "boolean"],
                ["negateComparison", "9", "2", "signed", "true", "boolean"],
                ["typedWrap", "9223372036854775807", "2", "signed", "true", "boolean"],
                ["multiplyConstant", "9", "2", "signed", "true", "boolean"],
                ["negativeConstant", "9", "2", "signed", "true", "boolean"],
                ["precisionBoundary", "9", "2", "signed", "true", "boolean"]
            ]
        } else if name.hasPrefix("visible-") {
            cases = [["f", "9", "2", "signed", "11", "signed"], ["recur", "2", "7", "signed", "7", "signed"]]
        } else {
            let kind = language == .javascript || language == .typescript ? "integer" : "signed"
            cases = [["f", "9", "2", kind, name == "depth-javascript" ? "1152" : "9", kind]]
        }
        for item in cases {
            let arguments = try [item[1], item[2]].map { try value($0, kind: item[3]) }
            let result = try IRInterpreter().run(program, entry: item[0], arguments: arguments)
            #expect(result.outcome == .returned(try value(item[4], kind: item[5])))
        }
        let files = try LeanEmitter().emit(program) + TLAEmitter().emit(program)
        let lean = try #require(files.first { $0.path == "lean/Generated/Program.lean" })
        let tla = try #require(files.first { $0.path == "tla/Program.tla" })
        #expect(try BackendArtifactDecoder().decodeLeanProgram(lean.contents) == program)
        #expect(try BackendArtifactDecoder().decodeTLAProgram(tla.contents) == program)
        if let output = ProcessInfo.processInfo.environment["FORMAL_REGRESSION_OUTPUT"] {
            let directory = URL(fileURLWithPath: output).appendingPathComponent(name)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try source.write(to: directory.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)
            let data = try JSONEncoder().encode(cases)
            try data.write(to: directory.appendingPathComponent("observations.json"))
            for file in files {
                let path = directory.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.write(to: path, atomically: true, encoding: .utf8)
            }
        }
    }
    private func value(_ decimal: String, kind: String) throws -> IRValue {
        switch kind {
        case "integer": return .integer(try MathematicalInteger(decimal))
        case "signed":
            let integer = try #require(Int64(decimal))
            let pattern = try BitPattern(width: 64, bits: UInt64(bitPattern: integer))
            return .bits(pattern)
        case "unsigned":
            let integer = try #require(UInt64(decimal))
            let pattern = try BitPattern(width: 64, bits: integer)
            return .bits(pattern)
        case "boolean": return .bits(try BitPattern(width: 1, bits: decimal == "true" ? 1 : 0))
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    @Test func handlesConstantTreesNearTheDepthLimit() throws {
        let expression = Array(repeating: "1", count: 127).joined(separator: "+")
        let source = "package main\nfunc f(a int64, b int64) bool { return " + expression + " < 0 }\n"
        let program = try ScalarSourceCompiler().compile(source, language: .go, moduleID: "Boundary")
        let bit = try BitPattern(width: 64, bits: 0)
        let result = try IRInterpreter().run(program, entry: "f", arguments: [.bits(bit), .bits(bit)])
        #expect(result.outcome == .returned(.bits(try BitPattern(width: 1, bits: 0))))
    }

    @Test func explicitWorkStackPreservesNestedCallArgumentOrder() throws {
        let source = """
        function encode(a, b) { return a * 10n + b; }
        function f(a, b) { return encode(encode(a, b), encode(b, a)) - encode(b, a); }
        """
        let program = try ScalarSourceCompiler().compile(source, language: .javascript, moduleID: "Order")
        let a = try MathematicalInteger("9")
        let b = try MathematicalInteger("2")
        let expected = try MathematicalInteger("920")
        let result = try IRInterpreter().run(program, entry: "f", arguments: [.integer(a), .integer(b)])
        #expect(result.outcome == .returned(.integer(expected)))
    }

}
