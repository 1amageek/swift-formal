import Foundation
import Testing
import FormalEvidence

@Suite(.timeLimit(.minutes(1)))
struct StateValueTests {
    @Test func exactTaggedValuesPreserveLargeIntegersAndBits() throws {
        let value = StateValue.record(["large":.integer("9007199254740993123456789"),"signed":.integer("-9007199254740993123456789"),"bits":.bitvector(width: 4,bits: "0010"),"nested":.sequence([.boolean(false),.set([.string("α")]),.opaque("function boundary")])])
        let bytes = try EvidenceIdentity.encode(value)
        let decoded = try JSONDecoder().decode(StateValue.self,from: bytes)
        #expect(decoded == value)
        let json = try #require(JSONSerialization.jsonObject(with: bytes) as? [String:Any])
        #expect(json["type"] as? String == "record")
        #expect(throws: FormalEvidenceError.self) { try EvidenceIdentity.encode(StateValue.integer("01")) }
        #expect(throws: FormalEvidenceError.self) { try EvidenceIdentity.encode(StateValue.bitvector(width: 4,bits: "10")) }
        for text in [#"{"type":"integer","value":9007199254740993}"#,#"{"type":"integer","value":"-0"}"#,#"{"type":"bitvector","value":"0020","width":4}"#,#"{"type":"future","value":0}"#,#"{"type":"integer","value":"1","extra":true}"#] {
            #expect(throws: (any Error).self) { try JSONDecoder().decode(StateValue.self,from: Data(text.utf8)) }
        }
    }
}
