import Foundation
import Testing
import ArgusCore
@testable import ArgusStore

func instant(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

@Test func recoveryDSTPolicyAndMinimumDateCapture() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var reminder = original
  reminder.dueAt = instant("2026-03-08T09:30:00Z")
  let quiet = try QuietHours(startHour: 1, startMinute: 0, endHour: 3, endMinute: 30, timeZoneID: "America/Los_Angeles")
  try store.save(reminder, expectedRevision: nil)
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  let reopened = try ReminderStore(databaseURL: url)
  #expect(try reopened.desiredSystemNotifications(now: instant("2026-03-08T09:00:00Z")).first?.fireAt == instant("2026-03-08T10:30:00Z"))
  #expect(try reopened.captureDueNotices(now: instant("2026-03-08T10:00:00Z")).insertedCount == 0)
  #expect(try reopened.captureDueNotices(now: instant("2026-03-08T10:30:00Z")).insertedCount == 1)
  try reopened.saveNotificationPolicy(NotificationPolicy(), expectedRevision: 2)
  var minimum = original
  minimum.id = UUID()
  minimum.dueAt = StoreDates.minimum
  try reopened.save(minimum, expectedRevision: nil)
  #expect(try reopened.captureDueNotices(now: StoreDates.minimum).insertedCount == 1)
  #expect(try reopened.notices().contains { $0.reminderID == minimum.id && $0.scheduledAt == StoreDates.minimum })
}

@Test func recoveryHistoricalCoalescedNoticeKeepsExactOccurrenceAndOnlyDismissesSelected() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var reminder = original
  reminder.dueAt = instant("2026-09-14T00:00:00Z")
  reminder.recurrence = .weekdays(hour: 0, minute: 0)
  reminder.alertOffsets = [0, 86400]
  let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
  try store.save(reminder, expectedRevision: nil)
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  let now = instant("2026-09-17T08:00:00Z")
  let capture = try store.captureDueNotices(now: now)
  #expect(capture.recurringScanStart == now.addingTimeInterval(-604800))
  let notices = try store.notices()
  let selected = try #require(notices.first { $0.scheduledAt == instant("2026-09-14T07:00:00Z") })
  let occurrence = instant("2026-09-15T00:00:00Z")
  #expect(selected.occurrenceDates == [reminder.dueAt, occurrence])
  #expect(throws: StoreError.noticeNoLongerApplicable(selected.id)) {
    try store.snoozeNotice(id: selected.id, occurrenceAt: now, until: now.addingTimeInterval(3600), expectedRevision: 1, now: now)
  }
  try store.snoozeNotice(id: selected.id, occurrenceAt: occurrence, until: now.addingTimeInterval(3600), expectedRevision: 1, now: now)
  let reopened = try ReminderStore(databaseURL: url)
  let saved = try #require(try reopened.reminder(id: reminder.id))
  #expect(saved.snoozedOccurrenceAt == occurrence)
  #expect(saved.dueAt == reminder.dueAt)
  #expect(try reopened.notices().count == notices.count - 1)
  #expect(try reopened.notices(includeDismissed: true).first { $0.id == selected.id }?.dismissedAt == now)
  #expect(try reopened.desiredSystemNotifications(now: now).contains { $0.fireAt == now.addingTimeInterval(3600) })
}

@Test func recoveryOldRecurrenceIsBoundedAndDeletionCascadesOnlyRelatedNotices() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var recurring = original
  recurring.dueAt = instant("2000-01-03T10:00:00Z")
  recurring.recurrence = .weekdays(hour: 10, minute: 0)
  try store.save(recurring, expectedRevision: nil)
  var other = original
  other.id = UUID()
  other.dueAt = instant("2000-01-01T00:00:00Z")
  try store.save(other, expectedRevision: nil)
  let now = instant("2026-09-17T11:00:00Z")
  _ = try store.captureDueNotices(now: now)
  let recurringNotices = try store.notices().filter { $0.reminderID == recurring.id }
  #expect(!recurringNotices.isEmpty)
  #expect(recurringNotices.allSatisfy { $0.scheduledAt >= now.addingTimeInterval(-604800) })
  try store.delete(id: recurring.id, expectedRevision: 1)
  let reopened = try ReminderStore(databaseURL: url)
  #expect(try reopened.notices(includeDismissed: true).map(\.reminderID) == [other.id])
  #expect(try reopened.reminder(id: recurring.id) == nil)
  #expect(try reopened.reminder(id: other.id) == other)
}

@Test func recoveryDismissRejectsNULSuffixAndIsIdempotent() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let now = reminder.dueAt
  _ = try store.captureDueNotices(now: now)
  let notice = try #require(store.notices().first)
  #expect(throws: StoreError.noticeNotFound(notice.id + "\0suffix")) { try store.dismissNotice(id: notice.id + "\0suffix", now: now) }
  #expect(try store.notices().count == 1)
  try store.dismissNotice(id: notice.id, now: now)
  try store.dismissNotice(id: notice.id, now: now.addingTimeInterval(5))
  #expect(try store.notices(includeDismissed: true).first?.dismissedAt == now)
  #expect(try store.generation() == 1)
  #expect(try store.list() == [reminder])
}

@Test(arguments: ["policy", "notice", "provenance", "foreignKey"])
func recoveryCorruptSchemaTwoIsNeverReset(kind: String) throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  _ = try store.captureDueNotices(now: reminder.dueAt)
  let database = try SQLiteDatabase(url: url)
  switch kind {
  case "policy": try database.execute("UPDATE notification_policy SET revision = 2")
  case "notice": try database.execute("UPDATE reminder_notices SET scheduled_at = scheduled_at + 1")
  case "foreignKey":
    try database.execute("PRAGMA foreign_keys = OFF")
    try database.execute("DELETE FROM reminders")
  default:
    let notice = try #require(store.notices().first)
    let invalid = NoticeRecord(id: notice.id, reminderID: reminder.id, titleSnapshot: reminder.title,
      scheduledAt: reminder.dueAt, sourceRevision: 1, capturedAt: reminder.dueAt, occurrenceDates: [])
    try database.statement("UPDATE reminder_notices SET payload = ?") { statement in
      try database.bind(JSONEncoder().encode(invalid), to: statement, at: 1)
      _ = try database.step(statement)
    }
  }
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: url) }
  #expect(try rawScalar(url, "SELECT count(*) FROM reminder_notices") == 1)
  #expect(try rawScalar(url, "PRAGMA user_version") == 2)
}

@Test func recoveryCompletedReminderCannotBlockSystemPlanningAtDateLimit() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var completed = original
  completed.dueAt = StoreDates.maximum
  completed.isCompleted = true
  try store.save(completed, expectedRevision: nil)
  let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  #expect(try store.desiredSystemNotifications(now: original.createdAt).isEmpty)
}

@Test func recoveryConcurrentCapturesInsertEachNoticeOnce() async throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let first = try ReminderStore(databaseURL: url)
  let second = try ReminderStore(databaseURL: url)
  var reminder = original
  reminder.alertOffsets = [0, 60]
  try first.save(reminder, expectedRevision: nil)
  let now = reminder.dueAt
  let inserted = try await withThrowingTaskGroup(of: Int.self) { group in
    for store in [first, second] { group.addTask { try store.captureDueNotices(now: now).insertedCount } }
    var total = 0
    for try await count in group { total += count }
    return total
  }
  #expect(inserted == 2)
  #expect(try first.notices().count == 2)
  #expect(try second.generation() == 1)
}

@Test func recoveryPolicyFailureRollsBackRevisionAndGeneration() throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let original = try store.notificationPolicy()
  let database = try SQLiteDatabase(url: url)
  try database.execute("CREATE TRIGGER fail_policy_generation BEFORE UPDATE ON store_metadata BEGIN SELECT RAISE(ABORT, 'fixture'); END")
  #expect(throws: (any Error).self) { try store.saveNotificationPolicy(NotificationPolicy(bypassQuietHours: true), expectedRevision: 1) }
  #expect(try store.notificationPolicy() == original)
  #expect(try store.generation() == 0)
}
