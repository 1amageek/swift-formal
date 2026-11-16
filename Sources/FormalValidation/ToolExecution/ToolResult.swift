import Foundation

public struct ToolResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String
    public let elapsedSeconds: Double
}
