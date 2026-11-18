import Foundation

struct TLCGraphAudit {
    static func reachedTerminal(_ path: URL) async throws -> Bool {
        var terminal = false
        try await BoundedRecordLines.read(path,maximumLineBytes: 262_144,maximumTotalBytes: 67_108_864) { line in
            if let record = try TLCDotRecord.parse(line), record.target == nil {
                var decoder = TLAStateDecoder(record.label,maximumDepth: 128)
                if let status = TLAStateDecoder.status(decoder.decode()), ["returned","trapped","panic","undefinedBehavior"].contains(status) { terminal = true }
            }
        }
        return terminal
    }
}
