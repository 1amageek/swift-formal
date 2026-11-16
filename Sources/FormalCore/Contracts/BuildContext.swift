import Foundation

public struct BuildContext: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let profileID: String
    public let compilerVersion: String
    public let targetTriple: String
    public let dataLayout: String
    public let languageMode: String
    public let sdkVersion: String
    public let silStage: String
    public let optimization: String
    public let ownership: String
    public let standardLibraryID: String
    public let runtimeID: String
    public let compilerArguments: [String]

    public func validate(against lock: ToolchainLock) throws {
        guard schemaVersion == 1, !dataLayout.isEmpty, !standardLibraryID.isEmpty,
              !runtimeID.isEmpty, !compilerArguments.isEmpty else {
            throw FormalDiagnostic(.invalidManifest, "Build context requires explicit layout, libraries, runtime, and compiler arguments.")
        }
        guard profileID == lock.profileID, compilerVersion == lock.compilerVersion,
              targetTriple == lock.targetTriple, languageMode == lock.languageMode,
              sdkVersion == lock.sdkVersion, silStage == lock.silStage,
              optimization == lock.optimization, ownership == lock.ownership else {
            throw FormalDiagnostic(.toolchainMismatch, "Build context differs from the toolchain lock.")
        }
    }
}
