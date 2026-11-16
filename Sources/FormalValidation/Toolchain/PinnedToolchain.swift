import Foundation
import FormalCore

public struct PinnedToolchain: ToolchainProviding {
    private let runner: any ToolExecuting
    public init(runner: any ToolExecuting = LocalToolRunner()) { self.runner = runner }

    public func verify(at root: URL) throws -> BundledToolchain {
        try platform()
        let policy = try ToolchainPolicy.bundled()
        let resolved = root.standardizedFileURL.resolvingSymlinksInPath()
        let actual = try FileDigest.inventory(resolved)
        guard actual == policy.inventorySHA256 else {
            throw FormalDiagnostic(.integrityMismatch, "Bundled toolchain inventory mismatch (expected \(policy.inventorySHA256), found \(actual)); reinstall formal", path: root.path)
        }
        return BundledToolchain(root: resolved, policy: policy)
    }

    public func prepare(at root: URL, cache: URL) async throws -> BundledToolchain {
        try platform()
        let manager = FileManager.default
        guard !manager.fileExists(atPath: root.path) else { throw FormalDiagnostic(.invalidArguments, "Toolchain destination already exists") }
        let policy = try ToolchainPolicy.bundled()
        try manager.createDirectory(at: cache, withIntermediateDirectories: true)
        let staging = root.deletingLastPathComponent().appendingPathComponent(".tools-\(UUID().uuidString)")
        try manager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let leanArchive = try await fetch(policy.lean, name: "lean-4.35.0-darwin_aarch64.zip", cache: cache, logs: staging)
            let javaArchive = try await fetch(policy.java, name: "temurin-21.0.13.tar.gz", cache: cache, logs: staging)
            let jar = try await fetch(policy.tla, name: "tla2tools.jar", cache: cache, logs: staging)
            let payload = staging.appendingPathComponent("payload")
            try manager.createDirectory(at: payload, withIntermediateDirectories: false)
            try await require("/usr/bin/tar", ["-xf", leanArchive.path, "-C", payload.path,
                "lean-4.35.0-darwin_aarch64/bin/lean", "lean-4.35.0-darwin_aarch64/bin/leanchecker", "lean-4.35.0-darwin_aarch64/bin/lake",
                "lean-4.35.0-darwin_aarch64/lib", "lean-4.35.0-darwin_aarch64/LICENSE", "lean-4.35.0-darwin_aarch64/LICENSES"], logs: staging)
            try manager.moveItem(at: payload.appendingPathComponent("lean-4.35.0-darwin_aarch64"), to: payload.appendingPathComponent("lean"))
            try await require("/usr/bin/tar", ["-xf", javaArchive.path, "-C", payload.path], logs: staging)
            try manager.moveItem(at: payload.appendingPathComponent("jdk-21.0.13+9-jre"), to: payload.appendingPathComponent("java"))
            try manager.copyItem(at: jar, to: payload.appendingPathComponent("tla2tools.jar"))
            _ = try verify(at: payload)
            try manager.moveItem(at: payload, to: root)
            try manager.removeItem(at: staging)
            return BundledToolchain(root: root, policy: policy)
        } catch {
            do { try manager.removeItem(at: staging) }
            catch let cleanup { throw FormalDiagnostic(.ioFailure, "Preparation failed (\(error)); cleanup failed (\(cleanup))") }
            throw error
        }
    }

    private func fetch(_ artifact: ToolchainPolicy.Artifact, name: String, cache: URL, logs: URL) async throws -> URL {
        let destination = cache.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: destination.path) {
            let hash = try FileDigest.sha256(destination)
            guard hash == artifact.sha256 else { throw FormalDiagnostic(.integrityMismatch, "Cached archive SHA-256 mismatch", path: destination.path) }
            return destination
        }
        let temporary = cache.appendingPathComponent(".download-\(UUID().uuidString)")
        do {
            try await require("/usr/bin/curl", ["--disable", "--fail", "--location", "--silent", "--show-error", "--proto", "=https", "--proto-redir", "=https", "--max-time", "600", "--output", temporary.path, artifact.url], logs: logs)
            let hash = try FileDigest.sha256(temporary)
            guard hash == artifact.sha256 else { throw FormalDiagnostic(.integrityMismatch, "Downloaded archive SHA-256 mismatch") }
            try FileManager.default.moveItem(at: temporary, to: destination)
        } catch {
            if FileManager.default.fileExists(atPath: temporary.path) { try FileManager.default.removeItem(at: temporary) }
            throw error
        }
        return destination
    }
    private func require(_ executable: String, _ arguments: [String], logs: URL) async throws {
        let result = try await runner.run(executable: URL(fileURLWithPath: executable), arguments: arguments,
            directory: logs, environment: ["PATH": "/usr/bin:/bin", "LANG": "C"], log: logs.appendingPathComponent(UUID().uuidString), timeout: 660, maximumOutputBytes: 1_048_576, maximumWorkspaceBytes: nil)
        guard result.exitCode == 0 else { throw FormalDiagnostic(.toolFailure, "\(executable) failed: \(result.standardError)") }
    }
    private func platform() throws {
        #if !os(macOS) || !arch(arm64)
        throw FormalDiagnostic(.unsupportedOperation, "Packaged verification supports macOS arm64 only")
        #endif
    }
}
