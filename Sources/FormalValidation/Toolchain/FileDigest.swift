import CryptoKit
import Foundation
import FormalCore

public enum FileDigest {
    public static func sha256(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { file.closeFile() }
        var digest = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty { digest.update(data: data) }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    public static func inventory(_ root: URL) throws -> String {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(atPath: root.path) else {
            throw FormalDiagnostic(.integrityMismatch, "Cannot enumerate bundled toolchain")
        }
        var entries: [String] = []
        while let relative = enumerator.nextObject() as? String {
            let url = root.appendingPathComponent(relative)
            guard !relative.contains("\n"), !relative.contains("\t") else { throw FormalDiagnostic(.integrityMismatch, "Invalid tool path") }
            let attributes = try manager.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeDirectory: continue
            case .typeSymbolicLink:
                let target = try manager.destinationOfSymbolicLink(atPath: url.path)
                guard !target.contains("\n"), !target.contains("\t"), !target.hasPrefix("/"),
                      url.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else {
                    throw FormalDiagnostic(.integrityMismatch, "Escaping tool symlink", path: url.path)
                }
                entries.append("L\t\(relative)\t\(target)\n")
            case .typeRegular:
                let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
                let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
                let hash = try sha256(url)
                entries.append("F\t\(relative)\t\(mode & 0o111)\t\(size)\t\(hash)\n")
            default: throw FormalDiagnostic(.integrityMismatch, "Unsupported tool file type", path: url.path)
            }
        }
        return sha256(Data(entries.sorted().joined().utf8))
    }
}
