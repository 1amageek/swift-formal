import FormalIR
import FormalLean
import FormalLowering
import FormalSIL
import FormalTLA
import Foundation
import Testing

struct BackendEmissionTests {
    @Test(.timeLimit(.minutes(1)))
    func emitsBothBackendsFromActualSIL() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: root.appendingPathComponent("Fixtures/SIL/Core.sil"), encoding: .utf8)
        let syntax = try CanonicalSILParser().parse(source, path: "Core.sil")
        let symbols = ["$s4Core8subtractys5Int64VAD_ADtF", "$s4Core16wrappingSubtractys5Int64VAD_ADtF", "$s4Core6chooseys5Int64VADF", "$s4Core4callys5Int64VAD_ADtF"]
        let lowered = try ScalarSILLowering().lower(syntax, moduleID: "Core", entries: symbols)
        let lean = try LeanEmitter().emit(lowered.program)
        let tla = try TLAEmitter().emit(lowered.program)
        let repeatedLean = try LeanEmitter().emit(lowered.program)
        let repeatedTLA = try TLAEmitter().emit(lowered.program)
        #expect(lean == repeatedLean)
        #expect(tla == repeatedTLA)
        #expect(!lowered.independentlyValidated)
        if let output = ProcessInfo.processInfo.environment["FORMAL_BACKEND_OUTPUT"] {
            let directory = URL(fileURLWithPath: output)
            for file in lean + tla {
                let destination = directory.appendingPathComponent(file.path)
                try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try file.contents.write(to: destination, atomically: true, encoding: .utf8)
            }
        }
    }
}
