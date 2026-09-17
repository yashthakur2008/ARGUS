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
      try prepareSchema()
    } catch {
      sqlite3_close(handle)
      handle = nil
      throw error
    }
  }

  deinit { sqlite3_close(handle) }

  func requireSingleChangedRow() throws {
    guard sqlite3_changes(handle) == 1 else {
      throw StoreError.corruption("Mutation did not affect exactly one row")
    }
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

  /// Journal transitions can return BUSY without invoking SQLite's busy handler.
  /// Retry only this idempotent setup operation, outside any transaction, with a
  /// monotonic budget. Disable the handler here so each attempt cannot add 2s.
  func enableWAL() throws {
    try check(sqlite3_busy_timeout(handle, 0))
    defer { _ = sqlite3_busy_timeout(handle, 2_000) }
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while true {
      do {
        try statement("PRAGMA journal_mode = WAL") { statement in
          guard try step(statement) == SQLITE_ROW,
            try text(statement, at: 0).lowercased() == "wal",
            try step(statement) == SQLITE_DONE else {
            throw StoreError.corruption("SQLite did not enable WAL journaling")
          }
        }
        return
      } catch let error as StoreError {
        guard case .sqlite(let code, _) = error, code == SQLITE_BUSY else { throw error }
        guard clock.now < deadline else { throw error }
        // The failed statement has finalized before waiting or retrying.
        sqlite3_sleep(10)
      }
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
    guard text.utf8.count <= Int(Int32.max) else { throw StoreError.corruption("Text binding is too large") }
    try check(text.withCString { sqlite3_bind_text(statement, index, $0, Int32(text.utf8.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) })
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
