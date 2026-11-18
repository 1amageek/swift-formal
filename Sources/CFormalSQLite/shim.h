#include <sqlite3.h>
// SQLite copies bound input before the caller's scoped borrow ends.
static inline int formal_sqlite_bind_text(sqlite3_stmt *statement, int index, const char *text) {
    return sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT);
}
static inline int formal_sqlite_bind_blob(sqlite3_stmt *statement, int index, const void *bytes, int count) {
    return sqlite3_bind_blob(statement, index, bytes, count, SQLITE_TRANSIENT);
}
