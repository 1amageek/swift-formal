import Foundation
import FormalCore

public struct PropertySpecification: Codable, Sendable {
    public struct Property: Codable, Sendable {
        public let name: String
        public let entry: String
        public let inputViews: [PropertyView]
        public let resultView: PropertyView
        public let requires: String
        public let ensures: String
    }
    public let schemaVersion: Int
    public let properties: [Property]

    public static func load(_ url: URL) throws -> Self {
        let data = try ArtifactJSON.readBytes(from: url, maximumBytes: 262_144)
        return try decode(data)
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 262_144 else { throw invalid("Property file exceeds 256 KiB") }
        let object: Any
        do { object = try JSONSerialization.jsonObject(with: data) }
        catch { throw invalid("Malformed JSON: \(error)") }
        guard let root = object as? [String: Any], Set(root.keys) == ["schemaVersion", "properties"],
              let entries = root["properties"] as? [[String: Any]], (1...16).contains(entries.count) else { throw invalid("Expected schemaVersion and 1...16 properties") }
        for entry in entries {
            guard Set(entry.keys) == ["name", "entry", "inputViews", "resultView", "requires", "ensures"] else { throw invalid("Unknown or missing property fields") }
        }
        let result: Self
        do { result = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw invalid("Malformed property specification: \(error)") }
        guard result.schemaVersion == 1, Set(result.properties.map(\.name)).count == result.properties.count else { throw invalid("Invalid schema or duplicate property names") }
        for property in result.properties {
            guard validName(property.name), validName(property.entry), property.inputViews.count <= 128 else { throw invalid("Invalid property name, entry or argument count") }
            _ = try PropertyExpressionParser.parse(property.requires, inputs: property.inputViews, result: nil, numberLiterals: property.resultView == .number)
            _ = try PropertyExpressionParser.parse(property.ensures, inputs: property.inputViews, result: property.resultView)
        }
        return result
    }
    private static func validName(_ name: String) -> Bool {
        !name.isEmpty && name.utf8.count <= 128 && name.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 95 }
    }
    static func invalid(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.invalidArguments, "Invalid property: \(message)") }
}
