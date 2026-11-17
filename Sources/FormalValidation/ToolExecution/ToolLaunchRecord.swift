import Foundation

struct ToolLaunchRecord: Codable {
    let id: String
    let executable: String
    let arguments: [String]
    let createdSeconds: UInt64
    var pid: Int32?
    var startSeconds: UInt64?
    var startMicroseconds: UInt64?
    var terminal: Bool
}
