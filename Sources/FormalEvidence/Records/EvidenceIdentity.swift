import CryptoKit
import Foundation

public enum EvidenceIdentity {
    public static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
    public static func id(_ domain: String, _ parts: String...) -> String {
        var data = Data(domain.utf8); data.append(0)
        for part in parts { data.append(contentsOf: String(part.utf8.count).utf8); data.append(58); data.append(contentsOf: part.utf8) }
        return digest(data)
    }
    public static func validID(_ id: String) -> Bool { id.utf8.count == 64 && id.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
}
