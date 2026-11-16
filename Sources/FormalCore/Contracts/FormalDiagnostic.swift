import Foundation

public struct FormalDiagnostic: Error, Codable, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Codable, Sendable {
        case invalidArguments = "INVALID_ARGUMENTS"
        case invalidManifest = "INVALID_MANIFEST"
        case toolchainMismatch = "TOOLCHAIN_MISMATCH"
        case integrityMismatch = "INTEGRITY_MISMATCH"
        case unsupportedOperation = "UNSUPPORTED_OPERATION"
        case unsupportedExternal = "UNSUPPORTED_EXTERNAL"
        case unsupportedOpcode = "UNSUPPORTED_OPCODE"
        case unsupportedAttribute = "UNSUPPORTED_ATTRIBUTE"
        case unsupportedType = "UNSUPPORTED_TYPE"
        case sourceParseFailed = "SOURCE_PARSE_FAILED"
        case silParseFailed = "SIL_PARSE_FAILED"
        case ioFailure = "IO_FAILURE"
        case timeout = "TIMEOUT"
        case interrupted = "INTERRUPTED"
        case toolFailure = "TOOL_FAILURE"
    }

    public let code: Code
    public let message: String
    public let path: String?

    public init(_ code: Code, _ message: String, path: String? = nil) {
        self.code = code
        self.message = message
        self.path = path
    }

    public var exitCode: Int32 {
        switch code {
        case .invalidArguments, .invalidManifest, .toolchainMismatch: 2
        case .unsupportedOperation, .unsupportedExternal, .unsupportedOpcode, .unsupportedAttribute, .unsupportedType: 3
        case .integrityMismatch, .sourceParseFailed, .silParseFailed: 4
        case .timeout, .interrupted: 6
        case .ioFailure, .toolFailure: 7
        }
    }

    public var description: String {
        let location = path.map { " [\($0)]" } ?? ""
        return "\(code.rawValue): \(message)\(location)"
    }
}
