import Testing
import Foundation
import FormalCompiler
import FormalIR
import FormalValidation

struct SourceFrontendTests {
    private var root: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent() }
    private func source(_ language: SourceLanguage) throws -> String {
        try String(contentsOf: root.appendingPathComponent("Fixtures/Sources/\(language.rawValue).source"), encoding: .utf8)
    }
    private func arguments(_ language: SourceLanguage, _ values: [Int64]) throws -> [IRValue] {
        try values.map { value in
            if [.python, .javascript, .typescript, .bun].contains(language) { return .integer(try MathematicalInteger(String(value))) }
            return .bits(try BitPattern(width: 64, bits: UInt64(bitPattern: value)))
        }
    }
    @Test(arguments: SourceLanguage.allCases) func convertsAndExecutes(_ language: SourceLanguage) throws {
        let input = try source(language)
        let program = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((input).utf8), language: language, moduleID: "Fixture")).program
        var observations: [[String]] = []
        for (a, b, expected) in [(Int64(2), Int64(9), Int64(19)), (9, 2, -7), (-3, 4, -11), (0, 0, 0)] {
            let actual = try arguments(language, [a, b])
            let result = try IRInterpreter().run(program, entry: "calculate", arguments: actual)
            let expectedValue = try arguments(language, [expected])[0]
            #expect(result.outcome == .returned(expectedValue))
            let decimal: String
            switch result.outcome {
            case .returned(.bits(let bits)): decimal = String(bits.signedValue)
            case .returned(.integer(let integer)): decimal = integer.description
            default: throw CocoaError(.coderInvalidValue)
            }
            observations.append([String(a), String(b), decimal])
        }
        let lean = try LeanEmitter().emit(program)
        let tla = try TLAEmitter().emit(program)
        let leanProgram = try #require(lean.first { $0.path == "lean/Generated/Program.lean" })
        let tlaProgram = try #require(tla.first { $0.path == "tla/Program.tla" })
        #expect(try BackendArtifactDecoder().decodeLeanProgram(leanProgram.contents) == program)
        #expect(try BackendArtifactDecoder().decodeTLAProgram(tlaProgram.contents) == program)
        if let output = ProcessInfo.processInfo.environment["FORMAL_FRONTEND_OUTPUT"] {
            let directory = URL(fileURLWithPath: output).appendingPathComponent(language.rawValue)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let observationData = try JSONEncoder().encode(observations)
            try observationData.write(to: directory.appendingPathComponent("observations.json"))
            for file in lean + tla {
                let path = directory.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.write(to: path, atomically: true, encoding: .utf8)
            }
        }
    }
    @Test(arguments: [SourceLanguage.python, .typescript, .javascript, .bun]) func preservesLargeIntegers(_ language: SourceLanguage) throws {
        let program = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((source(language)).utf8), language: language, moduleID: "Large")).program
        let a = try MathematicalInteger("10000000000000000000000000000000000000000")
        let b = try MathematicalInteger("20000000000000000000000000000000000000000")
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: [.integer(a), .integer(b)])
        let expected = try MathematicalInteger("200000000000000000000000000000000000000000000000000000000000000000000000000000001")
        #expect(result.outcome == .returned(.integer(expected)))
        let bounded = try IRInterpreter(maximumValueNodes: 20).run(program, entry: "calculate", arguments: [.integer(a), .integer(b)])
        #expect(bounded.outcome == .boundExceeded("values"))
    }
    @Test(arguments: [SourceLanguage.swift, .rust, .c, .cpp, .go]) func overflowMeaning(_ language: SourceLanguage) throws {
        let program = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((source(language)).utf8), language: language, moduleID: "Overflow")).program
        let actual = try arguments(language, [Int64.min, 1])
        let result = try IRInterpreter().run(program, entry: "calculate", arguments: actual)
        switch language {
        case .swift: #expect(result.outcome == .trapped("integer overflow"))
        case .rust: #expect(result.outcome == .failed(.panic, "integer overflow"))
        case .c, .cpp: #expect(result.outcome == .failed(.undefinedBehavior, "signed integer overflow"))
        default:
            let expected = try arguments(language, [Int64.min + 1])[0]
            #expect(result.outcome == .returned(expected))
        }
    }
    @Test(arguments: SourceLanguage.allCases) func rejectsUnsupportedOrWrongLanguage(_ language: SourceLanguage) throws {
        let input = try source(language)
        #expect(throws: (any Error).self) { try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((input + "\nclass Unsupported {}").utf8), language: language, moduleID: "Invalid")).program }
        let wrong: SourceLanguage = language == .python ? .javascript : .python
        #expect(throws: (any Error).self) { try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((input).utf8), language: wrong, moduleID: "Invalid")).program }
        #expect(throws: (any Error).self) { try ScalarSourceCompiler(maximumSourceBytes: 1).compile(SourceCompilationRequest(source: Data((input).utf8), language: language, moduleID: "Invalid")).program }
    }
    @Test func rejectsSemanticChanges() throws {
        let invalid: [(SourceLanguage, String)] = [
            (.javascript, "function f(a) { return a + 1n + 1; }"),
            (.typescript, "function f(a: number): bigint { return a + 1; }"),
            (.rust, "fn f(a: i64) -> i64 { let mut x = a; return x; }"),
            (.c, "#define VALUE 1\nint64_t f(int64_t a) { return a; }"),
            (.c, "int64_t f(int64_t a) { return a + 1; }"),
            (.cpp, "int64_t f(int64_t a) { return f(a) + a; }"),
            (.go, "package main\nfunc f(a int64) int64 { x := 1; return a + x }"),
            (.swift, "func f(_ a: Int64) -> Int64 { let x = 1; return a + x }"),
            (.python, "def f(a: int) -> int:\n    a = a + 1\n    return a\n"),
            (.python, "def f(a: int) -> bool:\n    return a < 1 < 2\n"),
            (.python, "def f(a: int) -> int:\n    return unknown(a)\n"),
            (.python, "def f(a: int) -> int:\n    if a < 0:\n        return a\n    else:\n        x = a\n")
        ]
        for (language, input) in invalid {
            #expect(throws: (any Error).self) { try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((input).utf8), language: language, moduleID: "Invalid")).program }
        }
    }
    @Test(arguments: SourceLanguage.allCases) func comparisonsPreserveOrder(_ language: SourceLanguage) throws {
        let input = try source(language)
        for op in ["<", ">", "<=", ">=", "==", "!="] {
            let changed = input.replacingOccurrences(of: "a < b", with: "a \(op) b")
            let program = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((changed).utf8), language: language, moduleID: "Compare")).program
            for (a, b) in [(Int64(-3), Int64(4)), (4, -3), (2, 2)] {
                let condition: Bool
                switch op {
                case "<": condition = a < b
                case ">": condition = a > b
                case "<=": condition = a <= b
                case ">=": condition = a >= b
                case "==": condition = a == b
                default: condition = a != b
                }
                let expected = condition ? a * b + 1 : b - a
                let actual = try arguments(language, [a, b])
                let result = try IRInterpreter().run(program, entry: "calculate", arguments: actual)
                #expect(result.outcome == .returned(try arguments(language, [expected])[0]))
            }
        }
    }
    @Test(arguments: [SourceLanguage.swift, .rust, .c, .cpp, .go]) func unsignedOverflow(_ language: SourceLanguage) throws {
        var input = try source(language)
        switch language {
        case .swift: input = input.replacingOccurrences(of: "Int64", with: "UInt64")
        case .rust: input = input.replacingOccurrences(of: "i64", with: "u64")
        case .c, .cpp: input = input.replacingOccurrences(of: "int64_t", with: "uint64_t").replacingOccurrences(of: "1LL", with: "1ULL")
        default: input = input.replacingOccurrences(of: "int64", with: "uint64")
        }
        let program = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((input).utf8), language: language, moduleID: "Unsigned")).program
        let actual: [IRValue] = [.bits(try BitPattern(width: 64, bits: .max)), .bits(try BitPattern(width: 64, bits: 1))]
        let result = try IRInterpreter().run(program, entry: "helper", arguments: actual)
        if language == .swift { #expect(result.outcome == .trapped("integer overflow")) }
        else if language == .rust { #expect(result.outcome == .failed(.panic, "integer overflow")) }
        else { #expect(result.outcome == .returned(.bits(try BitPattern(width: 64, bits: 0)))) }
    }
    @Test func malformedInputAndNestingFailWithoutTrapping() throws {
        for (language, text) in [(SourceLanguage.rust, "fn f(a:"), (.typescript, "function f(a:"), (.python, "def f(a:"), (.swift, "func f(_ a:")] {
            #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((text).utf8), language: language, moduleID: "Malformed")).program }
        }
        let chain = "function f(a) { return " + Array(repeating: "a", count: 300).joined(separator: "+") + "; }"
        #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((chain).utf8), language: .javascript, moduleID: "Nested")).program }
        let asi = "function f(a) { return /* newline\n */ a; }"
        #expect(throws: SourceDiagnostic.self) { try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((asi).utf8), language: .javascript, moduleID: "ASI")).program }
    }

    @Test func rejectsMutatedIntegerOutput() throws {
        let input = try source(.python)
        let program = try ScalarSourceCompiler().compile(SourceCompilationRequest(source: Data((input).utf8), language: .python, moduleID: "Mutation")).program
        let lean = try #require(LeanEmitter().emit(program).first { $0.path == "lean/Generated/Program.lean" })
        let tla = try #require(TLAEmitter().emit(program).first { $0.path == "tla/Program.tla" })
        let invalidLean = lean.contents.replacingOccurrences(of: ".multiply", with: ".divide")
        let invalidTLA = tla.contents.replacingOccurrences(of: "\"multiply\"", with: "\"divide\"")
        #expect(throws: (any Error).self) { try BackendArtifactDecoder().decodeLeanProgram(invalidLean) }
        #expect(throws: (any Error).self) { try BackendArtifactDecoder().decodeTLAProgram(invalidTLA) }
    }

}
