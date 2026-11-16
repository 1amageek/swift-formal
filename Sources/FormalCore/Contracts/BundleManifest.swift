public struct BundleManifest: Codable, Sendable, Equatable {
    public struct Module: Codable, Sendable, Equatable {
        public let id: String
        public let path: String
        public let sha256: String
        public let dependencies: [String]
    }

    public struct EntryPoint: Codable, Sendable, Equatable {
        public let moduleID: String
        public let symbol: String
    }

    public let schemaVersion: Int
    public let profileID: String
    public let modules: [Module]
    public let entryPoints: [EntryPoint]
    public let exclusions: [String]

    public func validate(against lock: ToolchainLock) throws {
        guard schemaVersion == 1, !modules.isEmpty, !entryPoints.isEmpty else {
            throw FormalDiagnostic(.invalidManifest, "A v1 bundle needs modules and explicit entry points.")
        }
        guard profileID == lock.profileID else {
            throw FormalDiagnostic(.toolchainMismatch, "Manifest profile differs from the lock.")
        }
        let ids = Set(modules.map(\.id))
        guard ids.count == modules.count, Set(modules.map(\.path)).count == modules.count else {
            throw FormalDiagnostic(.invalidManifest, "Duplicate module IDs or paths.")
        }
        let hex = Set("0123456789abcdef")
        for module in modules {
            guard !module.id.isEmpty, !module.path.isEmpty,
                  module.sha256.count == 64, module.sha256.allSatisfy(hex.contains),
                  module.dependencies.allSatisfy(ids.contains) else {
                throw FormalDiagnostic(.invalidManifest, "Invalid module identity, hash, or dependency closure.", path: module.path)
            }
        }
        guard entryPoints.allSatisfy({ ids.contains($0.moduleID) && !$0.symbol.isEmpty }) else {
            throw FormalDiagnostic(.invalidManifest, "Entry points must name a module and a mangled symbol.")
        }
    }
}
