import Darwin
import FormalCore
import Foundation

public struct LocalCompilerProbe: CompilerProbing {
    public let timeoutSeconds: Double
    public let maximumOutputBytes: Int

    public init(timeoutSeconds: Double = 10, maximumOutputBytes: Int = 1_048_576) {
        self.timeoutSeconds = timeoutSeconds
        self.maximumOutputBytes = maximumOutputBytes
    }

    public func probe() async throws -> CompilerIdentity {
        guard timeoutSeconds.isFinite, timeoutSeconds > 0,
              maximumOutputBytes > 0, maximumOutputBytes < Int.max else {
            throw FormalDiagnostic(.invalidArguments, "Compiler probe limits must be finite and positive.")
        }
        let manager = FileManager.default
        let directory = manager.temporaryDirectory.appendingPathComponent("swift-formal-\(UUID().uuidString)")
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        defer {
            do { try manager.removeItem(at: directory) }
            catch { fputs("swift-formal: temporary compiler probe cleanup failed: \(error)\n", stderr) }
        }
        let stdoutURL = directory.appendingPathComponent("stdout.json")
        let stderrURL = directory.appendingPathComponent("stderr.txt")
        guard manager.createFile(atPath: stdoutURL.path, contents: nil),
              manager.createFile(atPath: stderrURL.path, contents: nil) else {
            throw FormalDiagnostic(.ioFailure, "Cannot create compiler probe output files.")
        }
        let output = try FileHandle(forWritingTo: stdoutURL)
        defer { output.closeFile() }
        let errors = try FileHandle(forWritingTo: stderrURL)
        defer { errors.closeFile() }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swiftc", "-print-target-info"]
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch { throw FormalDiagnostic(.toolFailure, "Cannot start compiler probe: \(error)") }
        defer {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        let clock = ContinuousClock()
        let started = clock.now
        do {
            while process.isRunning {
                try Task.checkCancellation()
                if started.duration(to: clock.now) >= .seconds(timeoutSeconds) {
                    throw FormalDiagnostic(.timeout, "Compiler probe exceeded its deadline.")
                }
                for url in [stdoutURL, stderrURL] {
                    let attributes = try manager.attributesOfItem(atPath: url.path)
                    if let size = attributes[.size] as? NSNumber, size.intValue > maximumOutputBytes {
                        throw FormalDiagnostic(.toolFailure, "Compiler probe exceeded its output limit.")
                    }
                }
                try await Task.sleep(for: .milliseconds(10))
            }
        } catch is CancellationError {
            throw FormalDiagnostic(.interrupted, "Compiler probe was cancelled.")
        }
        let data = try ArtifactJSON.readBytes(from: stdoutURL, maximumBytes: maximumOutputBytes)
        let errorData = try ArtifactJSON.readBytes(from: stderrURL, maximumBytes: maximumOutputBytes)
        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errorData, as: UTF8.self)
            throw FormalDiagnostic(.toolFailure, "Compiler probe failed: \(detail)")
        }
        do { return try JSONDecoder().decode(CompilerIdentity.self, from: data) }
        catch { throw FormalDiagnostic(.toolFailure, "Invalid compiler identity response: \(error)") }
    }
}
