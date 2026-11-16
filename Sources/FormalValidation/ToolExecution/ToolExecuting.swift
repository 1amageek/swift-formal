import Foundation

public protocol ToolExecuting: Sendable {
    func run(executable: URL, arguments: [String], directory: URL, environment: [String: String],
             log: URL, timeout: Double, maximumOutputBytes: Int, maximumWorkspaceBytes: Int?) async throws -> ToolResult
}
