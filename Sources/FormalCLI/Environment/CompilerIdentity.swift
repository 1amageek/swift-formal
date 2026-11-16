import Foundation

public struct CompilerIdentity: Codable, Sendable, Equatable {
    public struct Target: Codable, Sendable, Equatable {
        public let triple: String
        public let pointerWidthInBits: Int
    }

    public let compilerVersion: String
    public let swiftCompilerTag: String
    public let target: Target
}
