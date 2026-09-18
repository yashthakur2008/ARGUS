import Foundation
import ArgusCore

extension ReminderStore {
  public func notificationPolicy() throws -> NotificationPolicy {
    try lock.withLock { try database.readPolicy() }
  }

  public func saveNotificationPolicy(_ policy: NotificationPolicy, expectedRevision: Int64) throws {
    try lock.withLock {
      try database.transaction {
        guard try database.readPolicy().revision == expectedRevision else { throw StoreError.conflict }
        guard expectedRevision < Int64.max else { throw StoreError.revisionOverflow }
        let saved = try NotificationPolicy(quietHours: policy.quietHours,
          bypassQuietHours: policy.bypassQuietHours, revision: expectedRevision + 1)
        try database.statement("UPDATE notification_policy SET revision = ?, payload = ? WHERE id = 1") { statement in
          try database.bind(saved.revision, to: statement, at: 1)
          try database.bind(JSONEncoder().encode(saved), to: statement, at: 2)
          _ = try database.step(statement)
          try database.requireSingleChangedRow()
        }
        try database.incrementGeneration()
      }
    }
  }

  public func captureDueNotices(now: Date) throws -> NoticeCaptureResult {
    try StoreDates.validate(now)
    let start = max(StoreDates.minimum, now.addingTimeInterval(-StoreDates.week))
    return try lock.withLock {
      try database.transaction {
        let policy = try database.readPolicy()
        var captured = Set(try database.readNotices().map(\.id))
        var inserted = 0
        for reminder in try database.readReminders() {
          let plans = try ScheduleCalculator.plannedNotifications(for: reminder,
            now: reminder.recurrence == nil ? StoreDates.minimum : start, horizon: now,
            quietHours: policy.quietHours, bypassQuietHours: policy.bypassQuietHours, includingStart: true)
          for plan in plans where captured.insert(plan.intent.id).inserted {
            let intent = plan.intent
            let record = NoticeRecord(id: intent.id, reminderID: intent.reminderID,
              titleSnapshot: intent.title, scheduledAt: intent.fireAt, sourceRevision: intent.sourceRevision,
              capturedAt: now, occurrenceDates: plan.occurrenceDates)
            try record.validate()
            try database.statement("INSERT INTO reminder_notices (id, reminder_id, scheduled_at, payload) VALUES (?, ?, ?, ?)") { statement in
              try database.bind(record.id, to: statement, at: 1)
              try database.bind(record.reminderID.uuidString, to: statement, at: 2)
              try database.bind(record.scheduledAt, to: statement, at: 3)
              try database.bind(JSONEncoder().encode(record), to: statement, at: 4)
              _ = try database.step(statement)
              try database.requireSingleChangedRow()
            }
            inserted += 1
          }
        }
        return NoticeCaptureResult(insertedCount: inserted,
          activeCount: try database.readNotices(includeDismissed: false).count, recurringScanStart: start)
      }
    }
  }

  public func notices(includeDismissed: Bool = false) throws -> [ReminderNotice] {
    try lock.withLock { try database.readNotices(includeDismissed: includeDismissed) }
  }

  public func dismissNotice(id: String, now: Date) throws {
    try StoreDates.validate(now)
    try lock.withLock {
      try database.transaction {
        guard let notice = try database.readNotices(id: id).first else { throw StoreError.noticeNotFound(id) }
        if notice.dismissedAt == nil { try dismissLocked(id: id, now: now) }
      }
    }
  }

  public func reminder(id: UUID) throws -> Reminder? {
    try lock.withLock { try database.readReminders(id: id).first }
  }

  public func snoozeNotice(id: String, occurrenceAt: Date, until: Date, expectedRevision: Int64, now: Date) throws {
    for date in [occurrenceAt, until, now] { try StoreDates.validate(date) }
    guard until > now else { throw StoreError.invalidSnooze }
    try lock.withLock {
      try database.transaction {
        guard let notice = try database.readNotices(id: id).first else { throw StoreError.noticeNotFound(id) }
        guard notice.dismissedAt == nil else { throw StoreError.noticeDismissed(id) }
        guard var reminder = try database.readReminders(id: notice.reminderID).first else {
          throw StoreError.noticeNoLongerApplicable(id)
        }
        guard reminder.revision == expectedRevision else { throw StoreError.conflict }
        guard !reminder.isCompleted, notice.occurrenceDates.contains(occurrenceAt) else {
          throw StoreError.noticeNoLongerApplicable(id)
        }
        // A reminder has one snooze slot. Never silently discard a future alert for
        // another occurrence when acting on an older notice. Legacy targets use dueAt.
        if let snooze = reminder.snoozedUntil,
          (reminder.snoozedOccurrenceAt ?? reminder.dueAt) != occurrenceAt {
          let policy = try database.readPolicy()
          let delivery = policy.bypassQuietHours
            ? snooze : policy.quietHours?.nextAllowedDate(for: snooze) ?? snooze
          try StoreDates.validate(delivery)
          if delivery > now { throw StoreError.activeSnoozeConflict }
        }
        reminder.snoozedUntil = until
        reminder.snoozedOccurrenceAt = occurrenceAt
        reminder.updatedAt = now
        // Core validation proves the persisted target is still an occurrence of the current source.
        do { try reminder.validate() }
        catch { throw StoreError.noticeNoLongerApplicable(id) }
        try saveLocked(reminder, expectedRevision: expectedRevision)
        try dismissLocked(id: id, now: now)
      }
    }
  }

  private func dismissLocked(id: String, now: Date) throws {
    try database.statement("UPDATE reminder_notices SET dismissed_at = ? WHERE id = ?") { statement in
      try database.bind(now, to: statement, at: 1)
      try database.bind(id, to: statement, at: 2)
      _ = try database.step(statement)
      try database.requireSingleChangedRow()
    }
  }
}
