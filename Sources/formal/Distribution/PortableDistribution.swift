import Foundation
import FormalCore
import FormalCompiler
import FormalValidation

struct PortableDistribution {
    static let version = "0.1.1"
    var executable: URL {
        get throws {
            guard let url = Bundle.main.executableURL else { throw FormalDiagnostic(.ioFailure, "Cannot locate formal executable") }
            return url.standardizedFileURL.resolvingSymlinksInPath()
        }
    }
    var toolsURL: URL { get throws { try executable.deletingLastPathComponent().appendingPathComponent("toolchain") } }

    func package(output: URL, cache: URL?) async throws {
        let manager = FileManager.default
        let sourceExecutable = try executable
        let sourceTools = try toolsURL
        guard !manager.fileExists(atPath: output.path) else { throw FormalDiagnostic(.invalidArguments, "Distribution already exists", path: output.path) }
        let stage = output.deletingLastPathComponent().appendingPathComponent(".distribution-\(UUID().uuidString)")
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        do {
            try manager.copyItem(at: sourceExecutable, to: stage.appendingPathComponent("formal"))
            for bundle in [CompilerResources.bundleURL, ToolchainPolicy.resourceBundle] {
                try manager.copyItem(at: bundle, to: stage.appendingPathComponent(bundle.lastPathComponent))
            }
            let destination = stage.appendingPathComponent("toolchain")
            if manager.fileExists(atPath: sourceTools.path) {
                let verifiedTools = try PinnedToolchain().verify(at: sourceTools)
                let result = try await LocalToolRunner().run(executable: URL(fileURLWithPath: "/bin/cp"), arguments: ["-cR", verifiedTools.root.path, destination.path],
                    directory: stage, log: stage.appendingPathComponent("copy"), timeout: 300, maximumOutputBytes: 1_048_576)
                guard result.exitCode == 0 else { throw FormalDiagnostic(.ioFailure, "Cannot copy bundled toolchain: \(result.standardError)") }
                try manager.removeItem(at: stage.appendingPathComponent("copy.stdout"))
                try manager.removeItem(at: stage.appendingPathComponent("copy.stderr"))
                _ = try PinnedToolchain().verify(at: destination)
            } else {
                guard let userCache = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                    throw FormalDiagnostic(.ioFailure, "Cannot locate the user cache directory")
                }
                let downloads = cache ?? userCache.appendingPathComponent("formal/downloads")
                _ = try await PinnedToolchain().prepare(at: destination, cache: downloads)
            }
            try Self.notices.write(to: stage.appendingPathComponent("THIRD-PARTY-NOTICES.txt"), atomically: true, encoding: .utf8)
            try Self.readme.write(to: stage.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
            try manager.moveItem(at: stage, to: output)
        } catch {
            do { try manager.removeItem(at: stage) }
            catch let cleanup { throw FormalDiagnostic(.ioFailure, "Packaging failed (\(error)); cleanup failed (\(cleanup))") }
            throw error
        }
    }

    func install(prefix: URL, cache: URL?) async throws -> URL {
        let manager = FileManager.default
        let binary = prefix.appendingPathComponent("bin/formal")
        let destination = prefix.appendingPathComponent("libexec/formal/\(Self.version)")
        guard !manager.fileExists(atPath: binary.path), !manager.fileExists(atPath: destination.path) else {
            throw FormalDiagnostic(.invalidArguments, "Install destination already exists")
        }
        try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manager.createDirectory(at: binary.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await package(output: destination, cache: cache)
        do { try manager.createSymbolicLink(atPath: binary.path, withDestinationPath: "../libexec/formal/\(Self.version)/formal") }
        catch { try manager.removeItem(at: destination); throw error }
        return binary
    }
    private static let readme = """
    formal \(version) — macOS arm64 portable distribution
    Run ./formal --help or ./formal install --prefix /your/chosen/prefix.
    This directory includes pinned Java, TLC, Lean and SwiftPM resource bundles.
    Keep these files together. Generation and checking run offline.
    Use check --properties for quantified generated-model proofs, or --scenario for finite cases.
    General source translation remains UNVALIDATED.

    """
    private static let notices = """
    Java: Eclipse Temurin 21.0.13+9 JRE, GPLv2 with Classpath Exception.
    Preserve toolchain/java/Contents/Home/legal, NOTICE, and release metadata.
    Corresponding source: https://github.com/adoptium/temurin21-binaries/releases/tag/jdk-21.0.13%2B9
    OpenJDK source revision: https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.13%2B9/OpenJDK21U-jdk-sources_21.0.13_9.tar.gz
    Lean 4.35.0: Apache-2.0; preserve toolchain/lean/LICENSE and LICENSES.
    Source: https://github.com/leanprover/lean4/tree/v4.35.0
    TLA+ tools 1.7.4: MIT; copyright (c) 2017 Microsoft Corporation.
    Source: https://github.com/tlaplus/tlaplus/tree/v1.7.4
    \(tlcLicense)
    """
    private static let tlcLicense = """
    MIT License

    Copyright (c) 2017 Microsoft Corporation

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

    """
}
