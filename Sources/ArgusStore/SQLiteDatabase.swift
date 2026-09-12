import Foundation
import CSQLite

/// Not Sendable. The owning ReminderStore must hold its lock for every operation.
final class SQLiteDatabase {
  private var handle: OpaquePointer?

  init(url: URL) throws {
    guard url.isFileURL else { throw StoreError.corruption("Database URL must be a file URL") }
    let code = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard code == SQLITE_OK else {
      let error = failure(code)
      sqlite3_close(handle)
      handle = nil
      throw error
    }
    do {
      try check(sqlite3_busy_timeout(handle, 2_000))
      // Reject unknown/nonempty unversioned databases before changing their file headers.
      _ = try checkedSchemaVersion()
      try execute("PRAGMA foreign_keys = ON")
      try execute("PRAGMA journal_mode = WAL")
      try execute("PRAGMA synchronous = FULL")
      try transaction {
        let version = try checkedSchemaVersion()
        if version == 0 {
          try execute("CREATE TABLE reminders (id TEXT PRIMARY KEY NOT NULL, revision INTEGER NOT NULL CHECK(revision > 0), payload BLOB NOT NULL)")
          try execute("CREATE TABLE store_metadata (id INTEGER PRIMARY KEY CHECK(id = 1), generation INTEGER NOT NULL CHECK(generation >= 0))")
          try execute("INSERT INTO store_metadata (id, generation) VALUES (1, 0)")
          try execute("PRAGMA user_version = 1")
        }
        guard try scalar("SELECT count(*) FROM store_metadata") == 1 else {
          throw StoreError.corruption("Invalid generation metadata")
        }
        _ = try generation()
        // Fail on an incompatible table immediately, without rebuilding or discarding it.
        try statement("SELECT id, revision, payload FROM reminders LIMIT 0") { _ in }
      }
    } catch {
      sqlite3_close(handle)
      handle = nil
      throw error
    }
  }

  deinit { sqlite3_close(handle) }

  private func checkedSchemaVersion() throws -> Int64 {
    let version = try scalar("PRAGMA user_version")
    if version == 0 {
      guard try scalar("SELECT count(*) FROM sqlite_master WHERE name NOT LIKE 'sqlite_%'") == 0 else {
        throw StoreError.corruption("Unversioned database is not empty")
      }
    } else if version != 1 {
      throw StoreError.unsupportedSchema(version)
    }
    return version
  }

  func failure(_ code: Int32) -> StoreError {
    .sqlite(code: code, message: handle.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open SQLite database")
  }

  func check(_ code: Int32) throws {
    guard code == SQLITE_OK else { throw failure(code) }
  }

  func statement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
    var prepared: OpaquePointer?
    let code = sqlite3_prepare_v2(handle, sql, -1, &prepared, nil)
    guard code == SQLITE_OK, let prepared else {
      sqlite3_finalize(prepared)
      throw failure(code)
    }
    defer { sqlite3_finalize(prepared) }
    return try body(prepared)
  }

  func step(_ statement: OpaquePointer) throws -> Int32 {
    let code = sqlite3_step(statement)
    guard code == SQLITE_ROW || code == SQLITE_DONE else { throw failure(code) }
    return code
  }

  func execute(_ sql: String) throws {
    try statement(sql) { statement in
      while try step(statement) == SQLITE_ROW {}
    }
  }

  func scalar(_ sql: String) throws -> Int64 {
    try statement(sql) { statement in
      guard try step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else {
        throw StoreError.corruption("Missing integer metadata")
      }
      let value = sqlite3_column_int64(statement, 0)
      guard try step(statement) == SQLITE_DONE else { throw StoreError.corruption("Duplicate metadata") }
      return value
    }
  }

  func generation() throws -> Int64 {
    let value = try scalar("SELECT generation FROM store_metadata WHERE id = 1")
    guard value >= 0 else { throw StoreError.corruption("Negative generation") }
    return value
  }

  func incrementGeneration() throws {
    guard try generation() < Int64.max else { throw StoreError.revisionOverflow }
    try execute("UPDATE store_metadata SET generation = generation + 1 WHERE id = 1")
  }

  func bind(_ text: String, to statement: OpaquePointer, at index: Int32) throws {
    try check(text.withCString { sqlite3_bind_text(statement, index, $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) })
  }

  func bind(_ value: Int64, to statement: OpaquePointer, at index: Int32) throws {
    try check(sqlite3_bind_int64(statement, index, value))
  }

  func bind(_ data: Data, to statement: OpaquePointer, at index: Int32) throws {
    try check(data.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) })
  }

  func transaction<T>(write: Bool = true, _ body: () throws -> T) throws -> T {
    try execute(write ? "BEGIN IMMEDIATE" : "BEGIN")
    do {
      let result = try body()
      try execute("COMMIT")
      return result
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }
}
