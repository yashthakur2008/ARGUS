import Foundation
import Testing
import ArgusCore
@testable import ArgusStore

@Test func recoveryPolicyPersistsDefersAndHonorsBypass() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let now = Date(timeIntervalSince1970: 1_800_054_000) // fixed UTC instant
  var reminder = original
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(secondsFromGMT: 0)!
  reminder.dueAt = calendar.date(bySettingHour: 23, minute: 0, second: 0, of: now)!
  let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
  try store.save(reminder, expectedRevision: nil)
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  let reopened = try ReminderStore(databaseURL: url)
  #expect(try reopened.notificationPolicy().quietHours == quiet)
  #expect(try reopened.notificationPolicy().revision == 2)
  #expect(try reopened.generation() == 2)
  let start = reminder.dueAt.addingTimeInterval(-3600)
  let end = reminder.dueAt.addingTimeInterval(86400)
  #expect(try reopened.desiredNotifications(now: start, horizon: end).first?.fireAt == quiet.nextAllowedDate(for: reminder.dueAt))
  #expect(throws: StoreError.conflict) { try reopened.saveNotificationPolicy(NotificationPolicy(), expectedRevision: 1) }
  try reopened.saveNotificationPolicy(NotificationPolicy(quietHours: quiet, bypassQuietHours: true), expectedRevision: 2)
  #expect(try reopened.desiredNotifications(now: start, horizon: end).first?.fireAt == reminder.dueAt)
  #expect(try reopened.list().first?.dueAt == reminder.dueAt)
}

@Test func recoveryCaptureDismissRestartAndTitleEditAreIdempotent() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let now = original.dueAt.addingTimeInterval(30 * 86400)
  var reminder = original
  reminder.alertOffsets = [0, 60]
  try store.save(reminder, expectedRevision: nil)
  let capture = try store.captureDueNotices(now: now)
  #expect(capture.insertedCount == 2)
  #expect(capture.activeCount == 2)
  let first = try #require(store.notices().first)
  try store.dismissNotice(id: first.id, now: now)
  let reopened = try ReminderStore(databaseURL: url)
  #expect(try reopened.captureDueNotices(now: now).insertedCount == 0)
  #expect(try reopened.captureDueNotices(now: now).activeCount == 1)
  #expect(try reopened.notices(includeDismissed: true).count == 2)
  reminder.title = "Renamed"
  try reopened.save(reminder, expectedRevision: 1)
  #expect(try reopened.captureDueNotices(now: now).insertedCount == 0)
  #expect(try reopened.notices().count == 1)
  #expect(try reopened.reminder(id: reminder.id)?.isCompleted == false)
  #expect(try reopened.reminder(id: UUID()) == nil)
  #expect(try reopened.generation() == 2)
}

@Test func recoveryAtomicNoticeSnoozeRollsBackAndPreservesDeadline() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let now = reminder.dueAt.addingTimeInterval(60)
  try store.save(reminder, expectedRevision: nil)
  _ = try store.captureDueNotices(now: now)
  let notice = try #require(store.notices().first)
  #expect(throws: StoreError.conflict) {
    try store.snoozeNotice(id: notice.id, occurrenceAt: reminder.dueAt, until: now.addingTimeInterval(600), expectedRevision: 2, now: now)
  }
  let database = try SQLiteDatabase(url: url)
  try database.execute("CREATE TRIGGER fail_dismiss BEFORE UPDATE ON reminder_notices BEGIN SELECT RAISE(ABORT, 'fixture'); END")
  #expect(throws: (any Error).self) {
    try store.snoozeNotice(id: notice.id, occurrenceAt: reminder.dueAt, until: now.addingTimeInterval(600), expectedRevision: 1, now: now)
  }
  #expect(try store.list() == [reminder])
  #expect(try store.notices().count == 1)
  #expect(try store.generation() == 1)
  try database.execute("DROP TRIGGER fail_dismiss")
  try store.snoozeNotice(id: notice.id, occurrenceAt: reminder.dueAt, until: now.addingTimeInterval(600), expectedRevision: 1, now: now)
  let reopened = try ReminderStore(databaseURL: url)
  let saved = try #require(try reopened.reminder(id: reminder.id))
  #expect(saved.dueAt == reminder.dueAt)
  #expect(saved.createdAt == reminder.createdAt)
  #expect(!saved.isCompleted)
  #expect(saved.snoozedOccurrenceAt == reminder.dueAt)
  #expect(saved.snoozedUntil == now.addingTimeInterval(600))
  #expect(saved.revision == 2)
  #expect(try reopened.notices().isEmpty)
  #expect(try reopened.generation() == 2)
}

@Test func recoveryPlansMonthAwayOneTimeButBoundsRecurrence() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let now = original.createdAt
  let store = try ReminderStore(databaseURL: url)
  var oneTime = original
  oneTime.dueAt = now.addingTimeInterval(30 * 86400)
  try store.save(oneTime, expectedRevision: nil)
  var recurring = original
  recurring.id = UUID()
  recurring.recurrence = .weekdays(hour: 10, minute: 0)
  try store.save(recurring, expectedRevision: nil)
  let plan = try ReminderStore(databaseURL: url).desiredSystemNotifications(now: now)
  #expect(plan.contains { $0.reminderID == oneTime.id && $0.fireAt == oneTime.dueAt })
  #expect(!plan.filter { $0.reminderID == recurring.id }.isEmpty)
  #expect(plan.filter { $0.reminderID == recurring.id }.allSatisfy { $0.fireAt <= now.addingTimeInterval(604800) })
  #expect(try store.desiredNotifications(now: now, horizon: now.addingTimeInterval(604800)).allSatisfy { $0.reminderID != oneTime.id })
}
