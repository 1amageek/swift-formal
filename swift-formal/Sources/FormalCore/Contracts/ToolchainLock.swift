import Foundation

public struct ToolchainLock: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let profileID: String
    public let compilerVersion: String
    public let compilerTag: String
    public let targetTriple: String
    public let pointerWidth: Int
    public let languageMode: String
    public let sdkVersion: String
    public let silStage: String
    public let optimization: String
    public let ownership: String
    public let runtimeModel: String
    public let semanticsVersion: String
    public let generationSupported: Bool

    public func validate() throws {
        guard schemaVersion == 1 else {
            throw FormalDiagnostic(.invalidManifest, "Unsupported toolchain lock schema.")
        }
        let fields = [profileID, compilerVersion, compilerTag, targetTriple, languageMode,
                      sdkVersion, ownership, runtimeModel, semanticsVersion]
        guard fields.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              [16, 32, 64, 128].contains(pointerWidth), languageMode == "6",
              silStage == "canonical", optimization == "-Onone" else {
            throw FormalDiagnostic(.invalidManifest, "Incomplete or incompatible bootstrap toolchain lock.")
        }
        guard !generationSupported, runtimeModel == "unimplemented", semanticsVersion == "unimplemented" else {
            throw FormalDiagnostic(.unsupportedOperation, "This bootstrap has no certified semantic profile.")
        }
    }
}
