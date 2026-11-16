import CryptoKit
import FormalCore
import Foundation
import Testing

struct BundleFixture {
    let root: URL
    let lock: ToolchainLock

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("formal-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("modules"), withIntermediateDirectories: true)
        let packageRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let lockData = try Data(contentsOf: packageRoot.appendingPathComponent("toolchain.lock.json"))
        lock = try JSONDecoder().decode(ToolchainLock.self, from: lockData)
        try lockData.write(to: root.appendingPathComponent("toolchain.lock.json"))
        let sil = Data("sil_stage canonical\n// Opaque integrity fixture.\n".utf8)
        try sil.write(to: root.appendingPathComponent("modules/Main.sil"))
        let digest = SHA256.hash(data: sil).map { String(format: "%02x", $0) }.joined()
        try write([
            "schemaVersion": 1, "profileID": lock.profileID,
            "modules": [["id": "Main", "path": "modules/Main.sil", "sha256": digest, "dependencies": []]],
            "entryPoints": [["moduleID": "Main", "symbol": "$s4Main5entryyyF"]], "exclusions": [],
        ], to: "manifest.json")
        try write([
            "schemaVersion": 1, "profileID": lock.profileID,
            "compilerVersion": lock.compilerVersion, "targetTriple": lock.targetTriple,
            "dataLayout": "fixture-layout", "languageMode": lock.languageMode,
            "sdkVersion": lock.sdkVersion, "silStage": lock.silStage,
            "optimization": lock.optimization, "ownership": lock.ownership,
            "standardLibraryID": "fixture-stdlib", "runtimeID": "fixture-runtime",
            "compilerArguments": ["-emit-sil", "-Onone"],
        ], to: "build-context.json")
    }

    func write(_ object: [String: Any], to path: String) throws {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try data.write(to: root.appendingPathComponent(path))
    }

    func mutate(_ path: String, _ body: (inout [String: Any]) -> Void) throws {
        let data = try Data(contentsOf: root.appendingPathComponent(path))
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        body(&object)
        try write(object, to: path)
    }

    func cleanup() {
        do { try FileManager.default.removeItem(at: root) }
        catch { Issue.record("Fixture cleanup failed: \(error)") }
    }
}
