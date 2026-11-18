import FormalEvidence
import Foundation

struct TrackedEmission {
    struct Span {
        let function: String
        let block: String?
        let instruction: Int?
        let start: Int
        let end: Int
    }
    private(set) var contents = ""
    private var spans: [Span] = []
    var byteCount: Int { contents.utf8.count }
    mutating func append(_ text: String) { contents += text }
    mutating func append(_ part: Self) {
        let offset = byteCount
        spans += part.spans.map { Span(function: $0.function, block: $0.block, instruction: $0.instruction, start: $0.start + offset, end: $0.end + offset) }
        contents += part.contents
    }
    mutating func mark(function: String, block: String? = nil, instruction: Int? = nil, start: Int) {
        spans.append(Span(function: function, block: block, instruction: instruction, start: start, end: byteCount))
    }
    func document(path: String, programDigest: String) -> GeneratedDocument {
        let digest = EvidenceIdentity.digest(Data(contents.utf8)), documentID = EvidenceIdentity.id("generated-document",path,digest)
        let origins = spans.enumerated().map { index, span in
            OriginLink(id: EvidenceIdentity.id("emitted-origin",documentID,String(index)), source: nil, address: IRAddress(programDigest: programDigest,function: span.function,block: span.block,instruction: span.instruction), generated: TextRange(documentID: documentID,start: span.start,end: span.end), precision: "generatedSegment",producer: path.hasSuffix(".lean") ? "lean-emitter/2" : "tla-emitter/2",synthetic: true)
        }
        return GeneratedDocument(path: path,contents: contents,origins: origins)
    }
}
