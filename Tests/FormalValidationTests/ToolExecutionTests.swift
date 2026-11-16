import Darwin
import Foundation
import FormalCore
import FormalValidation
import Testing

struct ToolExecutionTests {
    private func temporary(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("formal-runner-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        do { try await body(root) }
        catch { try FileManager.default.removeItem(at: root); throw error }
        try FileManager.default.removeItem(at: root)
    }

    @Test(.timeLimit(.minutes(1)))
    func capturesActualExitAndSeparateStreams() async throws {
        try await temporary { root in
            let result = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", "printf output; printf error >&2; exit 9"], directory: root,
                log: root.appendingPathComponent("result"))
            #expect(result.exitCode == 9)
            #expect(result.standardOutput == "output")
            #expect(result.standardError == "error")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func deadlineKillsDescendants() async throws {
        try await temporary { root in
            do {
                _ = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                    arguments: ["-c", "sleep 30 & echo $! > child; wait"], directory: root,
                    log: root.appendingPathComponent("result"), timeout: 0.2)
                Issue.record("Timeout returned success")
            } catch let error as FormalDiagnostic { #expect(error.code == .timeout) }
            let text = try String(contentsOf: root.appendingPathComponent("child"), encoding: .utf8)
            let pid = try #require(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
            for _ in 0..<40 {
                if kill(pid, 0) != 0 { break }
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(kill(pid, 0) == -1)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func workspaceBudgetRejectsCompletedOversizedOutput() async throws {
        try await temporary { root in
            do {
                _ = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/bin/dd"),
                    arguments: ["if=/dev/zero", "of=large", "bs=1024", "count=16"], directory: root,
                    log: root.appendingPathComponent("result"), maximumWorkspaceBytes: 1024)
                Issue.record("Workspace cap returned success")
            } catch let error as FormalDiagnostic { #expect(error.code == .timeout) }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func workspaceMonitoringAllowsChildTemporaryFileCleanup() async throws {
        try await temporary { root in
            let script = "i=0; while [ $i -lt 300 ]; do /bin/mkdir state; /usr/bin/touch state/file; /bin/rm -rf state; i=$((i+1)); done; printf completed"
            let result = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: ["-c", script], directory: root, log: root.appendingPathComponent("churn"),
                timeout: 20, maximumWorkspaceBytes: 1_048_576)
            #expect(result.exitCode == 0)
            #expect(result.standardOutput == "completed")
            #expect(result.standardError.isEmpty)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func cancellationAndOutputLimitCannotSucceed() async throws {
        try await temporary { root in
            let task = Task {
                try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"],
                    directory: root, log: root.appendingPathComponent("cancel"))
            }
            try await Task.sleep(for: .milliseconds(100))
            task.cancel()
            do { _ = try await task.value; Issue.record("Cancellation returned success") }
            catch { #expect(error is CancellationError) }
            do {
                _ = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/usr/bin/yes"), arguments: [],
                    directory: root, log: root.appendingPathComponent("flood"), maximumOutputBytes: 1000)
                Issue.record("Output cap returned success")
            } catch let error as FormalDiagnostic { #expect(error.code == .timeout) }
        }
    }
}
