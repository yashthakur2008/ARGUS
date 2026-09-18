import Foundation
import ArgusCore
import CSQLite

/// Synchronous SQLite repository. All connection, statement and transaction access is
/// protected by this lock, including reads. Pointers never escape the locked boundary.
/// SQLite WAL with synchronous=FULL provides durability, not encryption.
public final class ReminderStore: @unchecked Sendable {
  private let lock = NSLock()
  private let database: SQLiteDatabase

  public init(databaseURL: URL) throws {
    database = try SQLiteDatabase(url: databaseURL)
    // Decode existing records now so a corrupt database cannot look like an empty store.
    _ = try list()
  }

  public func list() throws -> [Reminder] {
    try lock.withLock { try readReminders() }
  }

  public func save(_ reminder: Reminder, expectedRevision: Int64?) throws {
    try reminder.validate()
    try lock.withLock {
      try database.transaction {
        let existing = try readReminders(id: reminder.id).first
        var saved = reminder
        if let expectedRevision {
          guard let existing, existing.revision == expectedRevision else { throw StoreError.conflict }
          guard expectedRevision < Int64.max else { throw StoreError.revisionOverflow }
          saved.revision = expectedRevision + 1
          saved.createdAt = existing.createdAt
        } else {
          guard existing == nil else { throw StoreError.conflict }
          saved.revision = 1
        }
        saved.alertOffsets = Set(saved.alertOffsets).sorted()
        try saved.validate()
        let payload = try JSONEncoder().encode(saved)
        let sql = existing == nil
          ? "INSERT INTO reminders (id, revision, payload) VALUES (?, ?, ?)"
          : "UPDATE reminders SET revision = ?2, payload = ?3 WHERE id = ?1"
        try database.statement(sql) { statement in
          try database.bind(saved.id.uuidString, to: statement, at: 1)
          try database.bind(saved.revision, to: statement, at: 2)
          try database.bind(payload, to: statement, at: 3)
          _ = try database.step(statement)
        }
        try database.incrementGeneration()
      }
    }
  }

  public func delete(id: UUID, expectedRevision: Int64) throws {
    try lock.withLock {
      try database.transaction {
        guard let existing = try readReminders(id: id).first,
          existing.revision == expectedRevision else { throw StoreError.conflict }
        try database.statement("DELETE FROM reminders WHERE id = ?") { statement in
          try database.bind(id.uuidString, to: statement, at: 1)
          _ = try database.step(statement)
        }
        try database.incrementGeneration()
      }
    }
  }

  public func generation() throws -> Int64 {
    try lock.withLock { try database.generation() }
  }

  public func desiredNotifications(now: Date, horizon: Date) throws -> [NotificationIntent] {
    try lock.withLock {
      try readReminders().flatMap {
        try ScheduleCalculator.notifications(for: $0, now: now, horizon: horizon)
      }.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
    }
  }

  private func readReminders(id: UUID? = nil) throws -> [Reminder] {
    let sql = "SELECT id, revision, payload FROM reminders" + (id == nil ? " ORDER BY id" : " WHERE id = ?")
    return try database.statement(sql) { statement in
      if let id { try database.bind(id.uuidString, to: statement, at: 1) }
      var reminders: [Reminder] = []
      while try database.step(statement) == SQLITE_ROW {
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
          sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
          sqlite3_column_type(statement, 2) == SQLITE_BLOB,
          let rawID = sqlite3_column_text(statement, 0),
          let bytes = sqlite3_column_blob(statement, 2) else {
          throw StoreError.corruption("Invalid reminder column types")
        }
        let metadataID = String(decoding: UnsafeBufferPointer(start: rawID,
          count: Int(sqlite3_column_bytes(statement, 0))), as: UTF8.self)
        let metadataRevision = sqlite3_column_int64(statement, 1)
        let payload = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 2)))
        let reminder: Reminder
        do { reminder = try JSONDecoder().decode(Reminder.self, from: payload) }
        catch { throw StoreError.corruption("Invalid reminder payload: \(error)") }
        guard reminder.id.uuidString == metadataID, reminder.revision == metadataRevision else {
          throw StoreError.corruption("Reminder metadata does not match payload")
        }
        reminders.append(reminder)
      }
      return reminders
    }
  }
}
