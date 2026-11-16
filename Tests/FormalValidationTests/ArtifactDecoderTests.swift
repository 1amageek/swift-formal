import FormalIR
import FormalLean
import FormalTLA
import FormalValidation
import Testing

struct ArtifactDecoderTests {
    private func program() throws -> IRProgram {
        let literal = try BitPattern(width: 64, bits: UInt64.max)
        return IRProgram(functions: [.init(moduleID: "Fixture", symbol: "entry", result: .bits(width: 64), blocks: [
            .init(id: "bb0", parameters: [], instructions: [.literal(destination: "%0", value: literal), .returnValue("%0")]),
        ])])
    }

    @Test(.timeLimit(.minutes(1)))
    func reparsesBothActualOutputLanguages() throws {
        let program = try program()
        let leanFiles = try LeanEmitter().emit(program)
        let tlaFiles = try TLAEmitter().emit(program)
        let lean = try #require(leanFiles.first { $0.path == "lean/Generated/Program.lean" })
        let tla = try #require(tlaFiles.first { $0.path == "tla/Program.tla" })
        let decoder = BackendArtifactDecoder()
        let decodedLean = try decoder.decodeLeanProgram(lean.contents)
        let decodedTLA = try decoder.decodeTLAProgram(tla.contents)
        #expect(decodedLean == program)
        #expect(decodedTLA == program)
        #expect(throws: (any Error).self) { try decoder.decodeLeanProgram(lean.contents + "\n#eval IO.println \"untrusted\"\n") }
        #expect(throws: (any Error).self) {
            try decoder.decodeTLAProgram(tla.contents.replacingOccurrences(of: "UNCHANGED state", with: "state' = state"))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func detectsChangedProgramData() throws {
        let program = try program()
        let files = try LeanEmitter().emit(program)
        let file = try #require(files.first { $0.path == "lean/Generated/Program.lean" })
        let mutated = file.contents.replacingOccurrences(of: "18446744073709551615", with: "7")
        let decoded = try BackendArtifactDecoder().decodeLeanProgram(mutated)
        #expect(decoded != program)
    }
}
