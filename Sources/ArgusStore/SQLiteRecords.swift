import Foundation
import ArgusCore
import CSQLite

/// These helpers are connection-confined. ReminderStore callers hold its lock.
extension SQLiteDatabase {
  func readReminders(id: UUID? = nil) throws -> [Reminder] {
    let sql = "SELECT id, revision, payload FROM reminders" + (id == nil ? " ORDER BY id" : " WHERE id = ?")
    return try statement(sql) { statement in
      if let id { try bind(id.uuidString, to: statement, at: 1) }
      var result: [Reminder] = []
      var identities = Set<UUID>()
      while try step(statement) == SQLITE_ROW {
        let metadataID = try text(statement, at: 0)
        guard sqlite3_column_type(statement, 1) == SQLITE_INTEGER else { throw StoreError.corruption("Invalid reminder revision") }
        let reminder: Reminder
        do { reminder = try JSONDecoder().decode(Reminder.self, from: blob(statement, at: 2)) }
        catch { throw StoreError.corruption("Invalid reminder payload") }
        guard reminder.id.uuidString == metadataID,
          reminder.revision == sqlite3_column_int64(statement, 1),
          identities.insert(reminder.id).inserted else {
          throw StoreError.corruption("Reminder identity or revision mismatch")
        }
        result.append(reminder)
      }
      return result
    }
  }

  func readPolicy() throws -> NotificationPolicy {
    try statement("SELECT revision, payload FROM notification_policy WHERE id = 1") { statement in
      guard try step(statement) == SQLITE_ROW,
        sqlite3_column_type(statement, 0) == SQLITE_INTEGER else { throw StoreError.corruption("Missing notification policy") }
      let policy: NotificationPolicy
      do { policy = try JSONDecoder().decode(NotificationPolicy.self, from: blob(statement, at: 1)) }
      catch { throw StoreError.corruption("Invalid notification policy") }
      guard policy.revision == sqlite3_column_int64(statement, 0), try step(statement) == SQLITE_DONE else {
        throw StoreError.corruption("Notification policy revision mismatch")
      }
      return policy
    }
  }

  func readNotices(includeDismissed: Bool = true, id: String? = nil) throws -> [ReminderNotice] {
    let clause = id != nil ? " WHERE id = ?" : (includeDismissed ? "" : " WHERE dismissed_at IS NULL")
    return try statement("SELECT id, reminder_id, scheduled_at, dismissed_at, payload FROM reminder_notices" + clause + " ORDER BY scheduled_at DESC, id") { statement in
      if let id { try bind(id, to: statement, at: 1) }
      var notices: [ReminderNotice] = []
      var identities = Set<String>()
      while try step(statement) == SQLITE_ROW {
        let record: NoticeRecord
        do { record = try JSONDecoder().decode(NoticeRecord.self, from: blob(statement, at: 4)) }
        catch { throw StoreError.corruption("Invalid notice payload") }
        try record.validate()
        let scheduledAt = try date(statement, at: 2)
        let dismissedAt = sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : try date(statement, at: 3)
        guard try text(statement, at: 0) == record.id,
          try text(statement, at: 1) == record.reminderID.uuidString,
          scheduledAt == record.scheduledAt, identities.insert(record.id).inserted else {
          throw StoreError.corruption("Notice metadata mismatch")
        }
        notices.append(record.notice(dismissedAt: dismissedAt))
      }
      return notices
    }
  }

  func text(_ statement: OpaquePointer, at column: Int32) throws -> String {
    guard sqlite3_column_type(statement, column) == SQLITE_TEXT, let bytes = sqlite3_column_text(statement, column) else {
      throw StoreError.corruption("Invalid text column")
    }
    return String(decoding: UnsafeBufferPointer(start: bytes, count: Int(sqlite3_column_bytes(statement, column))), as: UTF8.self)
  }

  func blob(_ statement: OpaquePointer, at column: Int32) throws -> Data {
    guard sqlite3_column_type(statement, column) == SQLITE_BLOB, let bytes = sqlite3_column_blob(statement, column) else {
      throw StoreError.corruption("Invalid payload column")
    }
    return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
  }

  func date(_ statement: OpaquePointer, at column: Int32) throws -> Date {
    guard [SQLITE_FLOAT, SQLITE_INTEGER].contains(sqlite3_column_type(statement, column)) else {
      throw StoreError.corruption("Invalid date column")
    }
    let date = Date(timeIntervalSinceReferenceDate: sqlite3_column_double(statement, column))
    try StoreDates.validate(date)
    return date
  }

  func bind(_ date: Date, to statement: OpaquePointer, at index: Int32) throws {
    try StoreDates.validate(date)
    try check(sqlite3_bind_double(statement, index, date.timeIntervalSinceReferenceDate))
  }
}

enum StoreDates {
  static let minimum = Date(timeIntervalSince1970: -62_135_596_800)
  static let maximum = Date(timeIntervalSince1970: 253_402_300_800.nextDown)
  static let week: TimeInterval = 604800
  static func validate(_ date: Date) throws {
    guard date.timeIntervalSince1970.isFinite, date >= minimum, date <= maximum else { throw CoreError.invalidDate }
  }
}

struct NoticeRecord: Codable {
  let id: String
  let reminderID: UUID
  let titleSnapshot: String
  let scheduledAt: Date
  let sourceRevision: Int64
  let capturedAt: Date
  let occurrenceDates: [Date]

  func validate() throws {
    do {
      for date in [scheduledAt, capturedAt] + occurrenceDates { try StoreDates.validate(date) }
      let checked = try Reminder(id: reminderID, title: titleSnapshot, dueAt: scheduledAt,
        timeZoneID: "UTC", createdAt: capturedAt, updatedAt: capturedAt, revision: sourceRevision)
      let key = String(scheduledAt.timeIntervalSinceReferenceDate.bitPattern, radix: 16)
      guard checked.title == titleSnapshot, !occurrenceDates.isEmpty,
        occurrenceDates == Set(occurrenceDates).sorted(),
        id == NotificationIntent.identifierPrefix + reminderID.uuidString.lowercased() + "." + key else {
        throw StoreError.corruption("Invalid notice identity or provenance")
      }
    } catch { throw StoreError.corruption("Invalid notice capture data") }
  }

  func notice(dismissedAt: Date?) -> ReminderNotice {
    ReminderNotice(id: id, reminderID: reminderID, titleSnapshot: titleSnapshot,
      scheduledAt: scheduledAt, sourceRevision: sourceRevision, capturedAt: capturedAt,
      occurrenceDates: occurrenceDates, dismissedAt: dismissedAt)
  }
}
