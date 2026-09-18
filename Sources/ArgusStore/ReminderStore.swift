import Foundation
import ArgusCore

/// All connection, statement and transaction access is protected by this lock.
/// Module-private helpers require the lock; pointers never escape the public boundary.
/// SQLite WAL with synchronous=FULL provides durability, not encryption.
public final class ReminderStore: @unchecked Sendable {
  let lock = NSLock()
  let database: SQLiteDatabase

  public init(databaseURL: URL) throws { database = try SQLiteDatabase(url: databaseURL) }

  public func list() throws -> [Reminder] { try lock.withLock { try database.readReminders() } }

  /// Policy-derived mutations may fence the policy snapshot as well as the reminder.
  /// Both checks and the write occur in one immediate transaction.
  public func save(_ reminder: Reminder, expectedRevision: Int64?, expectedPolicyRevision: Int64? = nil) throws {
    try lock.withLock {
      try database.transaction {
        if let expectedPolicyRevision {
          guard try database.readPolicy().revision == expectedPolicyRevision else { throw StoreError.conflict }
        }
        try saveLocked(reminder, expectedRevision: expectedRevision)
      }
    }
  }

  /// Caller holds the store lock and an immediate transaction.
  func saveLocked(_ reminder: Reminder, expectedRevision: Int64?) throws {
    try reminder.validate()
    let existing = try database.readReminders(id: reminder.id).first
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
      try database.requireSingleChangedRow()
    }
    try database.incrementGeneration()
  }

  public func delete(id: UUID, expectedRevision: Int64) throws {
    try lock.withLock {
      try database.transaction {
        guard let existing = try database.readReminders(id: id).first,
          existing.revision == expectedRevision else { throw StoreError.conflict }
        try database.statement("DELETE FROM reminders WHERE id = ?") { statement in
          try database.bind(id.uuidString, to: statement, at: 1)
          _ = try database.step(statement)
          try database.requireSingleChangedRow()
        }
        try database.incrementGeneration()
      }
    }
  }

  public func generation() throws -> Int64 { try lock.withLock { try database.generation() } }

  public func desiredNotifications(now: Date, horizon: Date) throws -> [NotificationIntent] {
    try lock.withLock {
      try database.transaction(write: false) {
        let policy = try database.readPolicy()
        return try database.readReminders().flatMap {
          try ScheduleCalculator.notifications(for: $0, now: now, horizon: horizon,
            quietHours: policy.quietHours, bypassQuietHours: policy.bypassQuietHours)
        }.sorted(by: notificationOrder)
      }
    }
  }
}

func notificationOrder(_ left: NotificationIntent, _ right: NotificationIntent) -> Bool {
  left.fireAt == right.fireAt ? left.id < right.id : left.fireAt < right.fireAt
}
