import CFormalSQLite
import Foundation

// Confined to one writer/reader actor. SQLite owns statement memory; every scoped
// input is copied by SQLITE_TRANSIENT, and row bytes are copied before finalization.
final class EvidenceDatabase {
    private var handle: OpaquePointer?
    init(_ url: URL, writable: Bool) throws {
        let flags = (writable ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY) | SQLITE_OPEN_NOFOLLOW
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let reason = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "No SQLite handle"
            if let handle { sqlite3_close(handle) }; handle = nil
            throw FormalEvidenceError.io("Cannot open evidence database at " + url.path + ": " + reason)
        }
        if writable { try execute("PRAGMA journal_mode=DELETE"); try execute("PRAGMA synchronous=FULL") }
    }
    deinit { if let handle { sqlite3_close(handle) } }
    func close() throws {
        guard let handle else { return }
        guard sqlite3_close(handle) == SQLITE_OK else { throw FormalEvidenceError.io("Database has unfinished statements") }
        self.handle = nil
    }
    func execute(_ sql: String, strings: [String] = [], blob: Data? = nil) throws {
        let statement = try prepare(sql, strings: strings, blob: blob); defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else { throw FormalEvidenceError.integrity("SQL write failed: \(code)") }
    }
    func records<T: Decodable>(_ sql: String, strings: [String] = [], maximumBytes: Int, as: T.Type) throws -> [T] {
        let statement = try prepare(sql, strings: strings, blob: nil); defer { sqlite3_finalize(statement) }
        var output: [T] = []; var total = 0
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return output }
            guard code == SQLITE_ROW, sqlite3_column_count(statement) >= 2 else { throw FormalEvidenceError.integrity("Invalid evidence row") }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count >= 0, count <= maximumBytes - total, let pointer = sqlite3_column_blob(statement, 0),
                let digestPointer = sqlite3_column_text(statement, 1) else { throw FormalEvidenceError.limit("Record read exceeds byte budget") }
            // The owned result crosses SQLite's statement lifetime, so a bounded copy is required.
            let bytes = Data(bytes: pointer, count: count); total += count
            guard EvidenceIdentity.digest(bytes) == String(cString: digestPointer) else { throw FormalEvidenceError.integrity("Record digest mismatch") }
            output.append(try JSONDecoder().decode(T.self, from: bytes))
        }
    }
    func bytes(_ key: String, maximum: Int) throws -> Data {
        let statement = try prepare("SELECT payload,digest FROM chunks WHERE id=?", strings: [key], blob: nil); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw FormalEvidenceError.missing("Document chunk") }
        let count = Int(sqlite3_column_bytes(statement, 0))
        guard count <= maximum, let pointer = sqlite3_column_blob(statement, 0), let digest = sqlite3_column_text(statement, 1) else { throw FormalEvidenceError.limit("Document chunk exceeds read budget") }
        let bytes = Data(bytes: pointer, count: count)
        guard EvidenceIdentity.digest(bytes) == String(cString: digest) else { throw FormalEvidenceError.integrity("Document chunk digest mismatch") }
        return bytes
    }
    func scalar(_ sql: String, strings: [String] = []) throws -> Int {
        let statement = try prepare(sql, strings: strings, blob: nil); defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw FormalEvidenceError.integrity("Missing scalar") }
        return Int(sqlite3_column_int64(statement, 0))
    }
    private func prepare(_ sql: String, strings: [String], blob: Data?) throws -> OpaquePointer {
        guard let handle else { throw FormalEvidenceError.closed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw FormalEvidenceError.integrity("Invalid database schema/query") }
        do {
            for (index, value) in strings.enumerated() {
                guard !value.utf8.contains(0), value.withCString({ formal_sqlite_bind_text(statement, Int32(index + 1), $0) }) == SQLITE_OK else { throw FormalEvidenceError.invalid("Invalid bound value") }
            }
            if let blob {
                guard blob.count <= Int(Int32.max) else { throw FormalEvidenceError.limit("SQL record size") }
                let code = blob.withUnsafeBytes { formal_sqlite_bind_blob(statement, Int32(strings.count + 1), $0.baseAddress, Int32($0.count)) }
                guard code == SQLITE_OK else { throw FormalEvidenceError.io("Cannot bind record") }
            }
            return statement
        } catch { sqlite3_finalize(statement); throw error }
    }
}
