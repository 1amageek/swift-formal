import Foundation
import FormalCore
import FormalIR

public struct VerificationScenario: Codable, Sendable {
    public struct Case: Codable, Sendable {
        public let name: String
        public let entry: String
        public let arguments: [String]
        public let expected: Expected
    }
    public struct Expected: Codable, Sendable {
        public let status: String
        public let value: String?
    }
    public let schemaVersion: Int
    public let fuel: Int
    public let cases: [Case]

    public static func load(_ url: URL) throws -> Self {
        let data = try ArtifactJSON.readBytes(from: url, maximumBytes: 262_144)
        return try decode(data)
    }
    public static func decode(_ data: Data) throws -> Self {
        let object = try JSONSerialization.jsonObject(with: data)
        guard let root = object as? [String: Any], Set(root.keys) == ["schemaVersion", "fuel", "cases"],
              let cases = root["cases"] as? [[String: Any]], !cases.isEmpty, cases.count <= 32 else { throw invalid() }
        for item in cases {
            guard Set(item.keys) == ["name", "entry", "arguments", "expected"], let expected = item["expected"] as? [String: Any],
                  Set(expected.keys).isSubset(of: ["status", "value"]), expected["status"] != nil else { throw invalid() }
        }
        let result: Self
        do { result = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw invalid() }
        guard result.schemaVersion == 1, (1...4096).contains(result.fuel),
              Set(result.cases.map(\.name)).count == result.cases.count else { throw invalid() }
        for item in result.cases {
            guard safeName(item.name), safeName(item.entry), item.arguments.count <= 128,
                  ["returned", "trapped", "panic", "undefinedBehavior"].contains(item.expected.status),
                  (item.expected.status == "returned") == (item.expected.value != nil),
                  (item.arguments + [item.expected.value].compactMap { $0 }).allSatisfy({ $0.utf8.count <= 257 }) else { throw invalid() }
        }
        return result
    }
    private static func safeName(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }
    }
    static func invalid() -> FormalDiagnostic { FormalDiagnostic(.invalidArguments, "Invalid scenario: require schemaVersion 1, fuel 1...4096 and 1...32 unique scalar cases") }
}
