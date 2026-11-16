import Foundation

public struct BundledToolchain: Sendable {
    public let root: URL
    public let policy: ToolchainPolicy
    public var java: URL { root.appendingPathComponent("java/Contents/Home/bin/java") }
    public var lean: URL { root.appendingPathComponent("lean/bin/lean") }
    public var jar: URL { root.appendingPathComponent("tla2tools.jar") }
    public var environment: [String: String] { ["PATH": "/usr/bin:/bin", "LANG": "C", "LC_ALL": "C"] }
}
