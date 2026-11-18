import Darwin
import Foundation
import FormalCore

/// Durable ownership for isolated-session launches tied to a private artifact root.
public struct ToolLaunchJournal: Sendable {
    private let directory: URL
    private let artifactRoot: URL
    public init(directory: URL, artifactRoot: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var info = stat()
        guard lstat(directory.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
            directory.resolvingSymlinksInPath().path == directory.standardizedFileURL.path else { throw FormalDiagnostic(.toolFailure, "Unsafe launch journal directory") }
        self.directory = directory; self.artifactRoot = artifactRoot.standardizedFileURL.resolvingSymlinksInPath()
    }
    func intent(executable: URL, arguments: [String]) throws -> ToolLaunchRecord {
        guard arguments.contains(where: { argument in
            guard argument.hasPrefix("/") else { return false }
            let path = URL(fileURLWithPath: argument).standardizedFileURL.resolvingSymlinksInPath().path
            return path.hasPrefix(artifactRoot.path + "/")
        }), arguments.count <= 256 else { throw FormalDiagnostic(.invalidArguments, "Journalled execution must bind a private artifact path") }
        let value = ToolLaunchRecord(id: UUID().uuidString, executable: executable.path, arguments: arguments, createdSeconds: UInt64(Date().timeIntervalSince1970), terminal: false)
        try write(value); return value
    }
    func spawned(_ record: ToolLaunchRecord, pid: Int32) throws -> ToolLaunchRecord {
        var info = proc_bsdinfo()
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
            info.pbi_uid == getuid(), info.pbi_pgid == UInt32(pid), getsid(pid) == pid else { throw FormalDiagnostic(.toolFailure, "Launch is not an owned isolated session") }
        var result = record; result.pid = pid; result.startSeconds = info.pbi_start_tvsec; result.startMicroseconds = info.pbi_start_tvusec
        try write(result); return result
    }
    func finish(_ record: ToolLaunchRecord) throws { var value = record; value.terminal = true; try write(value) }
    private func write(_ value: ToolLaunchRecord) throws {
        let bytes = try JSONEncoder().encode(value)
        guard bytes.count <= 32768 else { throw FormalDiagnostic(.invalidArguments, "Launch journal record exceeds its byte budget") }
        let file = directory.appendingPathComponent(value.id + ".json")
        try bytes.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let handle = try FileHandle(forWritingTo: file)
        do { try handle.synchronize(); try handle.close() }
        catch { do { try handle.close() } catch let cleanup { throw FormalDiagnostic(.toolFailure, "Journal sync failed (\(error)); close failed (\(cleanup))") }; throw error }
        let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { throw FormalDiagnostic(.toolFailure, "Cannot open launch journal directory for sync") }
        let syncResult = fsync(descriptor), closeResult = Darwin.close(descriptor)
        guard syncResult == 0, closeResult == 0 else { throw FormalDiagnostic(.toolFailure, "Cannot sync launch journal directory") }
    }
    /// The caller must hold exclusive ownership of the journal's workspace service.
    public func recover() async throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard files.count <= 4096 else { throw FormalDiagnostic(.timeout, "Launch recovery exceeds its record budget") }
        for file in files {
            let bytes = try ArtifactJSON.readBytes(from: file, maximumBytes: 32768)
            let record = try JSONDecoder().decode(ToolLaunchRecord.self, from: bytes)
            guard UUID(uuidString: record.id) != nil, file.lastPathComponent == record.id + ".json", record.executable.hasPrefix("/"), record.arguments.count <= 256 else { throw FormalDiagnostic(.toolFailure, "Invalid launch record identity") }
            guard record.arguments.contains(where: { $0.hasPrefix(artifactRoot.path + "/") }) else { throw FormalDiagnostic(.toolFailure, "Launch record has no private artifact binding") }
            if record.terminal { continue }
            var candidates: [(pid_t, UInt64, UInt64)] = []
            if let pid = record.pid, let seconds = record.startSeconds, let microseconds = record.startMicroseconds { candidates = [(pid, seconds, microseconds)] }
            else {
                // A crash may occur after suspended spawn but before its PID record is published.
                // Inspect only same-user processes executing the exact configured launcher, and
                // require all argv bytes (including unique private artifact paths) to match.
                var pids = [pid_t](repeating: 0, count: 65536)
                let count = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
                guard count >= 0, count < pids.count else { throw FormalDiagnostic(.toolFailure, "Cannot enumerate suspended launch recovery") }
                for pid in pids.prefix(Int(count)) where pid > 1 {
                    var info = proc_bsdinfo()
                    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == MemoryLayout<proc_bsdinfo>.size,
                        info.pbi_uid == getuid(), info.pbi_start_tvsec >= record.createdSeconds else { continue }
                    var path = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
                    let length = path.withUnsafeMutableBytes { proc_pidpath(pid, $0.baseAddress, UInt32($0.count)) }
                    guard length > 0, String(cString: path) == record.executable, try arguments(pid) == [record.executable] + record.arguments else { continue }
                    candidates.append((pid, info.pbi_start_tvsec, info.pbi_start_tvusec))
                }
                guard candidates.count <= 1 else { throw FormalDiagnostic(.toolFailure, "Ambiguous suspended process ownership") }
            }
            for (pid, seconds, microseconds) in candidates {
                var info = proc_bsdinfo()
                if proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(MemoryLayout<proc_bsdinfo>.size)) == 0 { continue }
                guard info.pbi_uid == getuid(), info.pbi_start_tvsec == seconds, info.pbi_start_tvusec == microseconds else { continue }
                guard info.pbi_pgid == UInt32(pid), getsid(pid) == pid else { throw FormalDiagnostic(.toolFailure, "Interrupted process left its isolated session") }
                if kill(-pid, SIGKILL) != 0 && errno != ESRCH { throw FormalDiagnostic(.toolFailure, "Cannot terminate interrupted session") }
                let deadline = ContinuousClock.now.advanced(by: .seconds(4))
                while kill(pid, 0) == 0 {
                    guard ContinuousClock.now < deadline else { throw FormalDiagnostic(.timeout, "Interrupted session has not been reaped") }
                    try await Task.sleep(for: .milliseconds(25))
                }
            }
            try finish(record)
        }
    }
    private func arguments(_ pid: pid_t) throws -> [String]? {
        var names: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid], size = 0
        let sized = names.withUnsafeMutableBufferPointer { sysctl($0.baseAddress, UInt32($0.count), nil, &size, nil, 0) }
        if sized != 0 { if errno == ESRCH || errno == ENOENT { return nil }; throw FormalDiagnostic(.toolFailure, "Cannot inspect suspended launch argv") }
        guard size >= 4, size <= 1_048_576 else { throw FormalDiagnostic(.toolFailure, "Process argv exceeds its recovery budget") }
        var bytes = [UInt8](repeating: 0, count: size)
        let read = names.withUnsafeMutableBufferPointer { names in bytes.withUnsafeMutableBytes { sysctl(names.baseAddress, UInt32(names.count), $0.baseAddress, &size, nil, 0) } }
        if read != 0 { if errno == ESRCH || errno == ENOENT { return nil }; throw FormalDiagnostic(.toolFailure, "Cannot read suspended launch argv") }
        // The initialized kernel buffer has at least four bytes; unaligned load avoids an alignment assumption.
        // Buffer pointers are borrowed only by synchronous sysctl/proc calls and never escape.
        let argc = bytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        guard (1...257).contains(argc) else { return nil }
        var offset = 4
        while offset < size && bytes[offset] != 0 { offset += 1 }
        while offset < size && bytes[offset] == 0 { offset += 1 }
        var result: [String] = []
        for _ in 0..<argc {
            let start = offset
            while offset < size && bytes[offset] != 0 { offset += 1 }
            guard offset < size, let value = String(bytes: bytes[start..<offset], encoding: .utf8) else { return nil }
            result.append(value); offset += 1
        }
        return result
    }
}
