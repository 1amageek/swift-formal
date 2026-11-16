import FormalCore
import SkeletonIndexCore
import SkeletonSwiftParser

public struct SkeletonSourceIndexer: SourceIndexing {
    public init() {}

    public func index(source: String, path: String) throws -> SourceIndex {
        let file = SwiftSkeletonParser().parse(path: path, source: source)
        guard !file.hasParseError else {
            throw FormalDiagnostic(.sourceParseFailed, "Swift declaration parser reported an error.", path: path)
        }
        var declarations = file.declarations.map {
            SourceIndex.Declaration(name: $0.signature, kind: $0.kind.rawValue,
                                    startLine: $0.range.startLine, endLine: $0.range.endLine)
        }
        for block in file.blocks {
            declarations.append(.init(name: block.typeName, kind: "type",
                                      startLine: block.range.startLine, endLine: block.range.endLine))
            for method in block.methods {
                declarations.append(.init(name: method.name, kind: "method",
                                          startLine: method.range.startLine, endLine: method.range.endLine))
            }
            for declaration in block.declarations {
                declarations.append(.init(name: declaration.signature, kind: declaration.kind.rawValue,
                                          startLine: declaration.range.startLine, endLine: declaration.range.endLine))
            }
        }
        return SourceIndex(path: path, declarations: declarations)
    }
}
