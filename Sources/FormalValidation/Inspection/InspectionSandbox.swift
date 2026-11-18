import Darwin
import Foundation
import FormalCore

struct InspectionSandbox {
    static func profile(read: [URL],write: URL) throws -> String {
        func quoted(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\\",with: "\\\\").replacingOccurrences(of: "\"",with: "\\\"") + "\"" }
        let physicalRead = try read.map { try physical($0) }
        let physicalWrite = try physical(write)
        let reads = physicalRead.map { "(subpath " + quoted($0) + ")" }.joined(separator: " ")
        return """
        (version 1)
        (deny default)
        (allow process-exec)
        (allow signal (target self))
        (allow sysctl-read)
        (allow file-read-metadata)
        (allow file-read* file-map-executable \(reads) (subpath "/System") (subpath "/usr/lib") (subpath "/usr/share") (subpath "/Library/Apple") (subpath "/private/var/db/dyld") (literal "/") (literal "/dev/null") (literal "/dev/urandom") (literal "/dev/random"))
        (allow file-write* (subpath \(quoted(physicalWrite))) (literal "/dev/null"))
        (allow file-read* (subpath \(quoted(physicalWrite))))
        (deny network*)
        (deny process-fork)
        """
    }
    private static func physical(_ url: URL) throws -> String {
        // OS-owned realpath allocation is borrowed only until String copies it;
        // exactly one free ends this scope. No pointer escapes into a task.
        guard let path = url.path.withCString({ realpath($0,nil) }) else { throw FormalDiagnostic(.ioFailure,"Cannot resolve sandbox resource root") }
        defer { free(path) }
        return String(cString: path)
    }
}
