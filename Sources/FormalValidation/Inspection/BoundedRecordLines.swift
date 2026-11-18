import Foundation
import CryptoKit
import FormalCore

struct BoundedRecordLines {
    @discardableResult
    static func read(_ path: URL,maximumLineBytes: Int,maximumTotalBytes: Int,isolation: isolated (any Actor)? = #isolation,body: (String) async throws -> Void) async throws -> String {
        let handle = try FileHandle(forReadingFrom: path)
        do {
            var pending = Data(), total = 0
            var digest = SHA256()
            while let chunk = try handle.read(upToCount: min(65_536,maximumLineBytes)), !chunk.isEmpty {
                try Task.checkCancellation()
                guard chunk.count <= maximumTotalBytes - total else { throw FormalDiagnostic(.unsupportedOperation,"Graph data exceeds its byte budget") }; total += chunk.count
                digest.update(data: chunk); pending.append(chunk)
                while let index = pending.firstIndex(of: 10) {
                    let length = pending.distance(from: pending.startIndex,to: index)
                    guard length <= maximumLineBytes, let text = String(data: pending.prefix(length),encoding: .utf8) else { throw FormalDiagnostic(.integrityMismatch,"Invalid graph record line") }
                    try await body(text); pending.removeSubrange(...index)
                }
                guard pending.count <= maximumLineBytes else { throw FormalDiagnostic(.unsupportedOperation,"Graph record exceeds line budget") }
            }
            if !pending.isEmpty {
                guard let text = String(data: pending,encoding: .utf8) else { throw FormalDiagnostic(.integrityMismatch,"Invalid final graph record") }; try await body(text)
            }
            try handle.close()
            return digest.finalize().map { String(format: "%02x",$0) }.joined()
        } catch { do { try handle.close() } catch let cleanup { throw FormalDiagnostic(.ioFailure,"Graph read failed (\(error)); close failed (\(cleanup))") }; throw error }
    }
}
