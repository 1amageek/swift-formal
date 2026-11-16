import Foundation

public enum ArtifactJSON {
    public static func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        let encoded = try encoder.encode(value)
        var result = encoded
        result.append(0x0A)
        return result
    }

    public static func read<Value: Decodable>(
        _ type: Value.Type, from url: URL, maximumBytes: Int = 1_048_576
    ) throws -> Value {
        let data = try readBytes(from: url, maximumBytes: maximumBytes)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw FormalDiagnostic(.invalidManifest, "Invalid JSON: \(error)", path: url.path)
        }
    }

    public static func readBytes(from url: URL, maximumBytes: Int) throws -> Data {
        guard maximumBytes > 0 && maximumBytes < Int.max else {
            throw FormalDiagnostic(.invalidArguments, "The byte limit must be positive and below Int.max.")
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw FormalDiagnostic(.invalidManifest, "Expected a regular file.", path: url.path)
            }
            let handle = try FileHandle(forReadingFrom: url)
            defer { handle.closeFile() }
            let data = try handle.read(upToCount: maximumBytes + 1) ?? Data()
            guard data.count <= maximumBytes else {
                throw FormalDiagnostic(.invalidManifest, "Input exceeds the byte limit.", path: url.path)
            }
            return data
        } catch let diagnostic as FormalDiagnostic {
            throw diagnostic
        } catch {
            throw FormalDiagnostic(.ioFailure, "Cannot read file: \(error)", path: url.path)
        }
    }
}
