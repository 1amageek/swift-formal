import Foundation
import Testing
import FormalEvidence
@testable import FormalValidation

@Suite(.timeLimit(.minutes(1)))
struct TLCStructureTests {
    @Test func typedStatePreservesValuesAndDoesNotInferTerminalFromText() {
        var parser = TLAStateDecoder(#"/\ state = [ status |-> "returned", n |-> -9007199254740993123456789, args |-> <<TRUE, {0, 1}, "α">> ]"#,maximumDepth: 32)
        let state = parser.decode()
        #expect(TLAStateDecoder.status(state) == "returned")
        guard case .record(let variables) = state, case .record(let fields) = variables["state"] else { Issue.record("Missing structured state"); return }
        #expect(fields["n"] == .integer("-9007199254740993123456789"))
        #expect(fields["args"] == .sequence([.boolean(true),.set([.integer("0"),.integer("1")]),.string("α")]))
        var unrelated = TLAStateDecoder(#"text = "state = [ status |-> returned""#,maximumDepth: 32)
        #expect(TLAStateDecoder.status(unrelated.decode()) == nil)
        var unknown = TLAStateDecoder(#"f = (0 :> 1 @@ 1 :> 2)"#,maximumDepth: 32)
        #expect(unknown.decode() == .record(["f":.opaque("(0 :> 1 @@ 1 :> 2)")]))
        var invalid = TLAStateDecoder(#"state = [ status |-> "re\qturned" ]"#,maximumDepth: 32)
        guard case .opaque = invalid.decode() else { Issue.record("Unknown escape was interpreted as a known string"); return }
    }
    @Test func actualDOTShapeSeparatesFingerprintsLabelsAndInitialAttribute() throws {
        let parsedNode = try TLCDotRecord.parse(#"-2375482345613397565 [label="/\ x = 1\n/\ y = \"style = filled\""];"#)
        let node = try #require(parsedNode)
        #expect(node.source == "-2375482345613397565" && node.target == nil && !node.initial)
        #expect(node.label == "/\\ x = 1\n/\\ y = \"style = filled\"")
        let parsedEdge = try TLCDotRecord.parse(#"6214856661242226081 -> -2375482345613397565 [label="Next",color="2"];"#)
        let edge = try #require(parsedEdge)
        #expect(edge.target == "-2375482345613397565" && edge.label == "Next")
        #expect(throws: FormalEvidenceError.self) { try TLCDotRecord.parse("123 [label=\"unfinished") }
    }
    @Test func orderedTraceAndLoopRequireMatchingFrames() throws {
        let output = """
        @!@!@STARTMSG 2217:4 @!@!@
        1: <Initial predicate>
        x = 0
        @!@!@ENDMSG 2217 @!@!@
        @!@!@STARTMSG 2217:4 @!@!@
        2: <Next line 4, col 1 to line 4, col 12 of module Probe>
        x = 1
        @!@!@ENDMSG 2217 @!@!@
        @!@!@STARTMSG 2122:4 @!@!@
        Back to state 1
        @!@!@ENDMSG 2122 @!@!@
        """
        let trace = try TLCTraceMessages.parse(output)
        #expect(trace.steps.map(\.text) == ["x = 0","x = 1"] && trace.loopBackIndex == 0)
        #expect(throws: FormalEvidenceError.self) { try TLCTraceMessages.parse(output.replacingOccurrences(of: "ENDMSG 2217",with: "ENDMSG 2110")) }
        #expect(throws: FormalEvidenceError.self) { try TLCTraceMessages.parse(output.replacingOccurrences(of: "2: <Next",with: "3: <Next")) }
    }
}
