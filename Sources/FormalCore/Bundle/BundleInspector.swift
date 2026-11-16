import CryptoKit
import Foundation

public struct BundleInspector: BundleInspecting {
    public let maximumModuleBytes: Int
    public let maximumBundleBytes: Int

    public init(maximumModuleBytes: Int = 16_777_216, maximumBundleBytes: Int = 67_108_864) {
        self.maximumModuleBytes = maximumModuleBytes
        self.maximumBundleBytes = maximumBundleBytes
    }

    public func inspect(at root: URL, expectedLock: ToolchainLock) throws -> BundleInspection {
        try expectedLock.validate()
        guard maximumModuleBytes > 0, maximumBundleBytes > 0 else {
            throw FormalDiagnostic(.invalidArguments, "Bundle limits must be positive.")
        }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        let lockURL = try contained("toolchain.lock.json", in: root)
        let lock = try ArtifactJSON.read(ToolchainLock.self, from: lockURL)
        try lock.validate()
        guard lock == expectedLock else {
            throw FormalDiagnostic(.toolchainMismatch, "Bundle lock differs from the caller's lock.", path: lockURL.path)
        }
        let contextURL = try contained("build-context.json", in: root)
        let context = try ArtifactJSON.read(BuildContext.self, from: contextURL)
        try context.validate(against: lock)
        let manifestURL = try contained("manifest.json", in: root)
        let manifest = try ArtifactJSON.read(BundleManifest.self, from: manifestURL)
        try manifest.validate(against: lock)
        var remaining = maximumBundleBytes
        var resolvedPaths = Set<String>()
        for module in manifest.modules {
            let url = try contained(module.path, in: root)
            guard url.pathExtension == "sil", resolvedPaths.insert(url.path).inserted else {
                throw FormalDiagnostic(.invalidManifest, "Expected distinct SIL module files.", path: url.path)
            }
            guard remaining > 0 else {
                throw FormalDiagnostic(.invalidManifest, "Bundle exceeds the total byte limit.")
            }
            let data = try ArtifactJSON.readBytes(from: url, maximumBytes: min(maximumModuleBytes, remaining))
            guard !data.isEmpty else {
                throw FormalDiagnostic(.invalidManifest, "Empty SIL module.", path: url.path)
            }
            remaining -= data.count
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == module.sha256 else {
                throw FormalDiagnostic(.integrityMismatch, "SIL module hash mismatch.", path: url.path)
            }
        }
        return BundleInspection(profileID: lock.profileID, moduleCount: manifest.modules.count,
                                entryPointCount: manifest.entryPoints.count)
    }

    private func contained(_ path: String, in root: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !components.contains(".."),
              !components.contains("."), !components.contains("") else {
            throw FormalDiagnostic(.invalidManifest, "Bundle paths must be canonical relative paths.", path: path)
        }
        let resolved = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(root.path + "/") else {
            throw FormalDiagnostic(.invalidManifest, "Bundle path escapes its root.", path: path)
        }
        return resolved
    }
}
