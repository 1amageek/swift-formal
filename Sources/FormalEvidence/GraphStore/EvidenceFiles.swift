import CryptoKit
import Darwin
import Foundation

struct EvidenceFiles {
    static func canonical(_ url: URL) throws -> URL {
        // realpath allocates one NUL-terminated path owned by this scope. The
        // pointer never escapes and is freed exactly once after String copies it.
        // Foundation's resolvingSymlinksInPath rewrites /private/var back to /var,
        // which violates SQLite OPEN_NOFOLLOW on macOS; retain the OS path verbatim.
        guard let path = url.path.withCString({ realpath($0, nil) }) else { throw FormalEvidenceError.io("Cannot resolve approved bundle root") }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path), isDirectory: true)
    }
    static func hash(_ url: URL, maximum: Int) throws -> (String, Int) {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            var hash = SHA256(); var count = 0
            while let data = try handle.read(upToCount: 65_536), !data.isEmpty {
                guard data.count <= maximum - count else { throw FormalEvidenceError.limit("Bundle exceeds database budget") }
                hash.update(data: data); count += data.count
            }
            try handle.close()
            return (hash.finalize().map { String(format: "%02x", $0) }.joined(), count)
        } catch { do { try handle.close() } catch let cleanup { throw FormalEvidenceError.io("Read failed: \(error); close failed: \(cleanup)") }; throw error }
    }
    static func read(_ url: URL,maximum: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        do {
            let data = try handle.read(upToCount: maximum + 1) ?? Data()
            guard data.count <= maximum else { throw FormalEvidenceError.limit("Manifest bytes") }
            try handle.close(); return data
        } catch {
            do { try handle.close() } catch let cleanup { throw FormalEvidenceError.io("Manifest read failed (\(error)); close failed (\(cleanup))") }
            throw error
        }
    }
    static func sync(_ url: URL) throws {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw FormalEvidenceError.io("Cannot open published content for sync") }
        defer { Darwin.close(descriptor) }
        guard fsync(descriptor) == 0 else { throw FormalEvidenceError.io("Cannot sync published content") }
    }
}
