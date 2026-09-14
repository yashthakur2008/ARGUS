import Foundation
import CSQLite

extension SQLiteDatabase {
  func prepareSchema() throws {
    // Preflight payloads as well as identities before persistent header changes.
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
      }
      if version < 2 {
        try execute("CREATE TABLE notification_policy (id INTEGER PRIMARY KEY CHECK(id = 1), revision INTEGER NOT NULL CHECK(revision > 0), payload BLOB NOT NULL)")
        try execute("CREATE TABLE reminder_notices (id TEXT PRIMARY KEY NOT NULL, reminder_id TEXT NOT NULL REFERENCES reminders(id) ON DELETE CASCADE, scheduled_at REAL NOT NULL, dismissed_at REAL, payload BLOB NOT NULL)")
        try execute("CREATE INDEX reminder_notices_active ON reminder_notices(dismissed_at, scheduled_at)")
        try execute("CREATE INDEX reminder_notices_source ON reminder_notices(reminder_id)")
        let payload = try JSONEncoder().encode(NotificationPolicy())
        try statement("INSERT INTO notification_policy (id, revision, payload) VALUES (1, 1, ?)") { statement in
          try bind(payload, to: statement, at: 1)
          _ = try step(statement)
        }
        try execute("PRAGMA user_version = 2")
      }
      _ = try checkedSchemaVersion()
    }
  }

  private func checkedSchemaVersion() throws -> Int64 {
    let version = try scalar("PRAGMA user_version")
    if version == 0 {
      guard try scalar("SELECT count(*) FROM sqlite_master WHERE name NOT GLOB 'sqlite_*'") == 0 else {
        throw StoreError.corruption("Unversioned database is not empty")
      }
      return version
    }
    guard version == 1 || version == 2 else { throw StoreError.unsupportedSchema(version) }
    try validateColumns("PRAGMA table_info(reminders)", expected: [
      ("id", "TEXT", 1, 1), ("revision", "INTEGER", 1, 0), ("payload", "BLOB", 1, 0)
    ])
    try validateColumns("PRAGMA table_info(store_metadata)", expected: [
      ("id", "INTEGER", 0, 1), ("generation", "INTEGER", 1, 0)
    ])
    guard try scalar("SELECT count(*) FROM store_metadata") == 1 else { throw StoreError.corruption("Invalid generation metadata") }
    _ = try generation()
    _ = try readReminders()
    if version == 2 {
      try validateColumns("PRAGMA table_info(notification_policy)", expected: [
        ("id", "INTEGER", 0, 1), ("revision", "INTEGER", 1, 0), ("payload", "BLOB", 1, 0)
      ])
      try validateColumns("PRAGMA table_info(reminder_notices)", expected: [
        ("id", "TEXT", 1, 1), ("reminder_id", "TEXT", 1, 0), ("scheduled_at", "REAL", 1, 0),
        ("dismissed_at", "REAL", 0, 0), ("payload", "BLOB", 1, 0)
      ])
      try statement("PRAGMA foreign_key_list(reminder_notices)") { statement in
        guard try step(statement) == SQLITE_ROW,
          try text(statement, at: 2) == "reminders", try text(statement, at: 3) == "reminder_id",
          try text(statement, at: 4) == "id", try text(statement, at: 6) == "CASCADE",
          try step(statement) == SQLITE_DONE else { throw StoreError.corruption("Missing notice deletion cascade") }
      }
      try statement("PRAGMA foreign_key_check") { statement in
        guard try step(statement) == SQLITE_DONE else { throw StoreError.corruption("Orphan notice source") }
      }
      guard try scalar("SELECT count(*) FROM notification_policy") == 1 else { throw StoreError.corruption("Invalid policy metadata") }
      _ = try readPolicy()
      _ = try readNotices()
    }
    return version
  }

  private func validateColumns(_ pragma: String, expected: [(String, String, Int32, Int32)]) throws {
    try statement(pragma) { statement in
      var index = 0
      while try step(statement) == SQLITE_ROW {
        guard index < expected.count else { throw StoreError.corruption("Incompatible schema") }
        let column = expected[index]
        guard try text(statement, at: 1) == column.0, try text(statement, at: 2).uppercased() == column.1,
          sqlite3_column_int(statement, 3) == column.2, sqlite3_column_int(statement, 5) == column.3 else {
          throw StoreError.corruption("Incompatible identity or column schema")
        }
        index += 1
      }
      guard index == expected.count else { throw StoreError.corruption("Missing schema columns") }
    }
  }
}
