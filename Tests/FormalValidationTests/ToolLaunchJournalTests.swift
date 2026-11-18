import FormalCore
import Darwin
import Foundation
@testable import FormalValidation
import Testing

struct ToolLaunchJournalTests {
    @Test(.timeLimit(.minutes(1))) func registeredSessionCanBeRecoveredWithoutItsObserver() async throws {
        try await exercise(removePID: false)
    }
    @Test(.timeLimit(.minutes(1))) func incompletePIDPublicationUsesExactPrivateLaunchArguments() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("formal-suspended-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let journal = try ToolLaunchJournal(directory: root.appendingPathComponent("journal"), artifactRoot: root)
        let arguments = ["-c", "sleep 30", root.appendingPathComponent("unique-owned-launch").path]
        _ = try journal.intent(executable: URL(fileURLWithPath: "/bin/sh"), arguments: arguments)
        var attributes: posix_spawnattr_t?
        #expect(posix_spawnattr_init(&attributes) == 0)
        defer { posix_spawnattr_destroy(&attributes) }
        #expect(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETSID | POSIX_SPAWN_START_SUSPENDED)) == 0)
        // The fixture owns initialized C strings until synchronous spawn returns; no pointer escapes.
        var argv = (["/bin/sh"] + arguments).map { strdup($0) }
        defer { for pointer in argv { free(pointer) } }
        #expect(argv.allSatisfy { $0 != nil }); argv.append(nil)
        var pid: pid_t = 0
        #expect(posix_spawn(&pid, "/bin/sh", nil, &attributes, &argv, nil) == 0)
        let ownedPID = pid
        let reap = Task.detached { var status: Int32 = 0; while waitpid(ownedPID, &status, 0) < 0 && errno == EINTR {}; return status }
        try await journal.recover()
        #expect(kill(pid, 0) == -1)
        _ = await reap.value
        try FileManager.default.removeItem(at: root)
    }
    private func exercise(removePID: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("formal-launch-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let journal = try ToolLaunchJournal(directory: root.appendingPathComponent("journal"), artifactRoot: root)
        let task = Task {
            try await LocalToolRunner(ownership: .isolatedSession, journal: journal).run(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo $$ > leader; sleep 30", root.appendingPathComponent("owned-argument").path], directory: root, log: root.appendingPathComponent("output"), timeout: 10)
        }
        let leader = root.appendingPathComponent("leader")
        for _ in 0..<100 { if FileManager.default.fileExists(atPath: leader.path) { break }; try await Task.sleep(for: .milliseconds(10)) }
        let text = try String(contentsOf: leader, encoding: .utf8)
        let pid = try #require(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        #expect(getsid(pid) == pid && getpgid(pid) == pid)
        if removePID {
            let file = try #require(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("journal"), includingPropertiesForKeys: nil).first)
            let bytes = try Data(contentsOf: file)
            var value = try JSONDecoder().decode(ToolLaunchRecord.self, from: bytes)
            value.pid = nil; value.startSeconds = nil; value.startMicroseconds = nil
            let changed = try JSONEncoder().encode(value); try changed.write(to: file, options: .atomic)
        }
        try await journal.recover()
        #expect(kill(pid, 0) == -1)
        let result = try await task.value
        #expect(result.exitCode != 0)
        #expect(kill(pid, 0) == -1)
        try FileManager.default.removeItem(at: root)
    }
}

extension ToolLaunchJournalTests {
    @Test(.timeLimit(.minutes(1))) func artifactBindingAcceptsOnlyActualCanonicalRoot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root,withIntermediateDirectories: true,attributes: [.posixPermissions: 0o700])
        defer { do { try FileManager.default.removeItem(at: root) } catch { Issue.record(error) } }
        let journal = try ToolLaunchJournal(directory: root.appendingPathComponent("journal"),artifactRoot: root)
        let input = root.appendingPathComponent("input"); try Data("input".utf8).write(to: input)
        let record = try journal.intent(executable: URL(fileURLWithPath: "/usr/bin/true"),arguments: [input.path])
        #expect(!record.terminal)
        #expect(throws: FormalDiagnostic.self) { try journal.intent(executable: URL(fileURLWithPath: "/usr/bin/true"),arguments: ["/etc/passwd"]) }
        try await journal.recover()
    }
}
