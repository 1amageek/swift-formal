import Darwin
import Foundation
import FormalCore

public struct LocalToolRunner: ToolExecuting {
    public init() {}

    public func run(executable: URL, arguments: [String], directory: URL,
                    environment: [String: String] = [:], log: URL,
                    timeout: Double = 120, maximumOutputBytes: Int = 8_388_608, maximumWorkspaceBytes: Int? = nil) async throws -> ToolResult {
        guard timeout.isFinite, timeout > 0, maximumOutputBytes > 0, maximumWorkspaceBytes.map({ $0 > 0 }) ?? true else {
            throw FormalDiagnostic(.invalidArguments, "Invalid process limits")
        }
        try Task.checkCancellation()
        let out = log.appendingPathExtension("stdout")
        let err = log.appendingPathExtension("stderr")
        let stdoutFD = open(out.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard stdoutFD >= 0 else { throw failure("Cannot create stdout log") }
        defer { close(stdoutFD) }
        let stderrFD = open(err.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard stderrFD >= 0 else { throw failure("Cannot create stderr log") }
        defer { close(stderrFD) }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { throw failure("Cannot create spawn actions") }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { throw failure("Cannot create spawn attributes") }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawn_file_actions_adddup2(&actions, stdoutFD, STDOUT_FILENO) == 0,
              posix_spawn_file_actions_adddup2(&actions, stderrFD, STDERR_FILENO) == 0,
              posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0) == 0,
              posix_spawn_file_actions_addchdir_np(&actions, directory.path) == 0,
              posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
              posix_spawnattr_setpgroup(&attributes, 0) == 0 else { throw failure("Cannot configure child process") }
        let values = [executable.path] + arguments
        let variables = environment.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        guard (values + variables).allSatisfy({ !$0.utf8.contains(0) }) else { throw failure("NUL in process input") }
        // Each C string is owned here, remains initialized through posix_spawn, and never escapes.
        // Pointer arrays are borrowed only by the spawn call; every allocation is freed exactly once.
        var argv = values.map { strdup($0) }
        var envp = variables.map { strdup($0) }
        defer { for pointer in argv { free(pointer) }; for pointer in envp { free(pointer) } }
        guard argv.allSatisfy({ $0 != nil }), envp.allSatisfy({ $0 != nil }) else { throw failure("Cannot allocate process arguments") }
        argv.append(nil); envp.append(nil)
        var pid: pid_t = 0
        let clock = ContinuousClock()
        let start = clock.now
        let code = posix_spawn(&pid, executable.path, &actions, &attributes, &argv, &envp)
        guard code == 0 else { throw failure("Cannot launch \(executable.lastPathComponent): \(code)") }
        var nextBudgetCheck = start
        var reaped = false
        defer {
            // A subprocess may have left descendants even after its leader exited.
            kill(-pid, SIGKILL)
            if !reaped { var status: Int32 = 0; while waitpid(pid, &status, 0) < 0 && errno == EINTR {} }
        }
        while true {
            try Task.checkCancellation()
            if let maximumWorkspaceBytes, clock.now >= nextBudgetCheck {
                try checkWorkspace(directory, maximumBytes: maximumWorkspaceBytes)
                nextBudgetCheck = clock.now.advanced(by: .milliseconds(250))
            }
            var outputStat = stat(); var errorStat = stat()
            guard fstat(stdoutFD, &outputStat) == 0, fstat(stderrFD, &errorStat) == 0 else { throw failure("Cannot inspect logs") }
            guard outputStat.st_size <= maximumOutputBytes, errorStat.st_size <= maximumOutputBytes else {
                throw FormalDiagnostic(.timeout, "Tool output exceeded its byte limit")
            }
            let duration = start.duration(to: clock.now).components
            let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
            guard seconds < timeout else { throw FormalDiagnostic(.timeout, "Tool exceeded \(timeout) seconds") }
            var status: Int32 = 0
            let waited = waitpid(pid, &status, WNOHANG)
            if waited == pid {
                reaped = true
                kill(-pid, SIGKILL)
                if let maximumWorkspaceBytes { try checkWorkspace(directory, maximumBytes: maximumWorkspaceBytes) }
                let output = try ArtifactJSON.readBytes(from: out, maximumBytes: maximumOutputBytes)
                let errors = try ArtifactJSON.readBytes(from: err, maximumBytes: maximumOutputBytes)
                let exitCode = status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f)
                return ToolResult(exitCode: exitCode, standardOutput: String(decoding: output, as: UTF8.self),
                                  standardError: String(decoding: errors, as: UTF8.self), elapsedSeconds: seconds)
            }
            guard waited == 0 || errno == EINTR else { throw failure("Cannot reap child") }
            try await Task.sleep(for: .milliseconds(25))
        }
    }

    private func checkWorkspace(_ directory: URL, maximumBytes: Int) throws {
        guard let enumerator = FileManager.default.enumerator(atPath: directory.path) else { throw failure("Cannot inspect tool workspace") }
        var total: UInt64 = 0
        var count = 0
        while let relative = enumerator.nextObject() as? String {
            count += 1
            let path = directory.appendingPathComponent(relative).path
            let attributes: [FileAttributeKey: Any]
            do { attributes = try FileManager.default.attributesOfItem(atPath: path) }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                // The child may remove temporary state between enumeration and inspection.
                continue
            }
            let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            guard count <= 10_000, size <= UInt64(maximumBytes), total <= UInt64(maximumBytes) - size else {
                throw FormalDiagnostic(.timeout, "Tool workspace exceeded its resource budget")
            }
            total += size
        }
    }

    private func failure(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.toolFailure, message) }
}
