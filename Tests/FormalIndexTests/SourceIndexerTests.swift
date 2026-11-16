import FormalIndex
import Foundation
import Testing

struct SourceIndexerTests {
    @Test(.timeLimit(.minutes(1)))
    func preservesActorAndPrivateMethod() throws {
        let source = "actor Inventory {\n private var stock = 1\n private func reserve() -> Bool { stock > 0 }\n}"
        let result = try SkeletonSourceIndexer().index(source: source, path: "Inventory.swift")
        #expect(result.declarations.contains { $0.name == "Inventory" && $0.startLine == 1 })
        #expect(result.declarations.contains { $0.name.contains("reserve") && $0.startLine == 3 })
        #expect(!result.providesExecutionSemantics)
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsInvalidSwift() {
        #expect(throws: (any Error).self) {
            try SkeletonSourceIndexer().index(source: "actor Inventory { func broken(", path: "bad.swift")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resolvesTrustedPackageOnly() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let resolver = SkeletonProjectMetadataResolver()
        #expect(throws: (any Error).self) { try resolver.resolve(at: root.path, trustedProject: false) }
        let resolved = try resolver.resolve(at: root.path, trustedProject: true)
        let result = try #require(resolved)
        #expect(result.packageName == "swift-formal")
        #expect(result.targets.contains { $0.name == "FormalCore" })
        #expect(!result.isCaptureBuildPlan)
    }
}
