import Foundation
import Testing
import ArgusCore
@testable import ArgusStore

@Test func recoveryRejectsReplacingDifferentActiveSnooze() throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var reminder = original
  reminder.dueAt = instant("2026-09-14T10:00:00Z")
  reminder.recurrence = .weekdays(hour: 10, minute: 0)
  reminder.alertOffsets = [0]
  try store.save(reminder, expectedRevision: nil)
  let now = instant("2026-09-16T11:00:00Z")
  _ = try store.captureDueNotices(now: now)
  let notices = try store.notices()
  let monday = try #require(notices.first { $0.occurrenceDates == [reminder.dueAt] })
  let tuesdayDate = instant("2026-09-15T10:00:00Z")
  let tuesday = try #require(notices.first { $0.occurrenceDates == [tuesdayDate] })
  let firstUntil = now.addingTimeInterval(600)
  try store.snoozeNotice(id: monday.id, occurrenceAt: reminder.dueAt,
    until: firstUntil, expectedRevision: 1, now: now)
  let before = try #require(try store.reminder(id: reminder.id))
  let generation = try store.generation()

  #expect(throws: StoreError.activeSnoozeConflict) {
    try store.snoozeNotice(id: tuesday.id, occurrenceAt: tuesdayDate,
      until: now.addingTimeInterval(1200), expectedRevision: 2, now: now)
  }

  let reopened = try ReminderStore(databaseURL: url)
  #expect(try reopened.reminder(id: reminder.id) == before)
  #expect(try reopened.generation() == generation)
  #expect(try reopened.notices().contains { $0.id == tuesday.id })
  let plan = try reopened.desiredSystemNotifications(now: now)
  #expect(plan.contains { $0.fireAt == firstUntil })
  #expect(!plan.contains { $0.fireAt == now.addingTimeInterval(1200) })
}

@Test(arguments: [false, true])
func recoveryPreservesLegacyAndQuietDeferredSnoozes(deferredByQuietHours: Bool) throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var reminder = original
  reminder.dueAt = instant("2026-09-14T10:00:00Z")
  reminder.recurrence = .weekdays(hour: 10, minute: 0)
  reminder.alertOffsets = [0]
  try store.save(reminder, expectedRevision: nil)
  let now = instant("2026-09-16T06:30:00Z")
  _ = try store.captureDueNotices(now: now)
  let target = instant("2026-09-15T10:00:00Z")
  let notice = try #require(try store.notices().first { $0.occurrenceDates == [target] })
  reminder.snoozedUntil = now.addingTimeInterval(deferredByQuietHours ? -1800 : 600)
  // A legacy missing target still refers to the original anchor, not the chosen notice.
  reminder.snoozedOccurrenceAt = nil
  try store.save(reminder, expectedRevision: 1)
  if deferredByQuietHours {
    let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  }
  let before = try store.list()
  let generation = try store.generation()
  #expect(throws: StoreError.activeSnoozeConflict) {
    try store.snoozeNotice(id: notice.id, occurrenceAt: target,
      until: now.addingTimeInterval(600), expectedRevision: 2, now: now)
  }
  #expect(try store.list() == before)
  #expect(try store.generation() == generation)
  #expect(try store.notices().contains { $0.id == notice.id })
}

@Test(arguments: ["sameTarget", "expired", "atDeadline", "bypassQuietHours"])
func recoveryAllowsNonConflictingSnoozes(scenario: String) throws {
  let (url, original) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var reminder = original
  reminder.dueAt = instant("2026-09-14T10:00:00Z")
  reminder.recurrence = .weekdays(hour: 10, minute: 0)
  reminder.alertOffsets = [0]
  try store.save(reminder, expectedRevision: nil)
  let now = instant("2026-09-16T06:30:00Z")
  _ = try store.captureDueNotices(now: now)
  let target = scenario == "sameTarget" ? reminder.dueAt : instant("2026-09-15T10:00:00Z")
  let notice = try #require(try store.notices().first { $0.occurrenceDates == [target] })
  reminder.snoozedOccurrenceAt = reminder.dueAt
  reminder.snoozedUntil = now.addingTimeInterval(scenario == "sameTarget" ? 300 : (scenario == "atDeadline" ? 0 : -60))
  try store.save(reminder, expectedRevision: 1)
  if scenario == "bypassQuietHours" {
    let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet, bypassQuietHours: true), expectedRevision: 1)
  }
  let until = now.addingTimeInterval(600)
  try store.snoozeNotice(id: notice.id, occurrenceAt: target, until: until, expectedRevision: 2, now: now)
  let reopened = try ReminderStore(databaseURL: url)
  let saved = try #require(try reopened.reminder(id: reminder.id))
  #expect(saved.snoozedOccurrenceAt == target)
  #expect(saved.snoozedUntil == until)
  #expect(saved.revision == 3)
  #expect(try reopened.notices(includeDismissed: true).first { $0.id == notice.id }?.dismissedAt == now)
}
