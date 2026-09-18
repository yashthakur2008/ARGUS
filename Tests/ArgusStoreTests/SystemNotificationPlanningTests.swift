import Foundation
import Testing
import ArgusCore
@testable import ArgusStore

@Test func systemPlanningRetainsFoldDeferredAdvanceAlertAfterReopenAndDeadline() throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let now = instant("2026-11-01T08:00:00Z")
  let due = instant("2026-11-01T09:15:00Z") // Second local 01:15, outside quiet hours.
  let deferred = instant("2026-11-01T10:00:00Z")
  let reminder = try Reminder(title: "Fold", dueAt: due, timeZoneID: "America/Los_Angeles",
    createdAt: now, updatedAt: now, alertOffsets: [0, 1500])
  let quiet = try QuietHours(startHour: 1, startMinute: 45, endHour: 2, endMinute: 0,
    timeZoneID: "America/Los_Angeles")
  do {
    let store = try ReminderStore(databaseURL: url)
    try store.save(reminder, expectedRevision: nil)
    try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  }
  let reopened = try ReminderStore(databaseURL: url)
  // The advance alert is first-local 01:50 and defers past the deadline to 02:00 PST.
  #expect(try reopened.desiredSystemNotifications(now: now).map(\.fireAt) == [due, deferred])
  #expect(try reopened.desiredSystemNotifications(now: instant("2026-11-01T09:30:00Z")).map(\.fireAt) == [deferred])
  #expect(try reopened.desiredNotifications(now: now, horizon: due).map(\.fireAt) == [due])
  #expect(try reopened.reminder(id: reminder.id)?.dueAt == due)

  try reopened.saveNotificationPolicy(NotificationPolicy(quietHours: quiet, bypassQuietHours: true), expectedRevision: 2)
  #expect(try reopened.desiredSystemNotifications(now: now).map(\.fireAt) == [instant("2026-11-01T08:50:00Z"), due])
}

@Test(arguments: [false, true])
func systemPlanningSnoozeReplacesEvenOutOfRangeOriginalCandidates(emptyOffsets: Bool) throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let now = instant("2026-11-01T08:00:00Z")
  let due = instant("2026-11-01T09:15:00Z")
  let reminder = try Reminder(title: "Snoozed fold", dueAt: due, timeZoneID: "America/Los_Angeles",
    createdAt: now, updatedAt: now, alertOffsets: emptyOffsets ? [] : [0, 1500, .greatestFiniteMagnitude],
    snoozedUntil: instant("2026-11-01T08:50:00Z"), snoozedOccurrenceAt: due)
  let quiet = try QuietHours(startHour: 1, startMinute: 45, endHour: 2, endMinute: 0,
    timeZoneID: "America/Los_Angeles")
  try store.save(reminder, expectedRevision: nil)
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  #expect(try store.desiredSystemNotifications(now: now).map(\.fireAt) == [instant("2026-11-01T10:00:00Z")])
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet, bypassQuietHours: true), expectedRevision: 2)
  #expect(try store.desiredSystemNotifications(now: now).map(\.fireAt) == [instant("2026-11-01T08:50:00Z")])
  #expect(try store.reminder(id: reminder.id)?.dueAt == due)
}

@Test(arguments: [false, true])
func systemPlanningSkipsAbsentCandidatesAtDateLimit(completed: Bool) throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let now = instant("2026-09-18T00:00:00Z")
  let reminder = try Reminder(title: "No alerts", dueAt: StoreDates.maximum, timeZoneID: "UTC",
    createdAt: now, updatedAt: now, alertOffsets: completed ? [0] : [], isCompleted: completed)
  let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
  try store.save(reminder, expectedRevision: nil)
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  #expect(try store.desiredSystemNotifications(now: now).isEmpty)
}

@Test(arguments: [false, true])
func systemPlanningRejectsUnsupportedRawAndDeferredCandidates(bypass: Bool) throws {
  let (url, _) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  let now = instant("2026-09-18T00:00:00Z")
  var reminder = try Reminder(title: "Date boundary", dueAt: now, timeZoneID: "UTC",
    createdAt: now, updatedAt: now, alertOffsets: [.greatestFiniteMagnitude])
  let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
  try store.save(reminder, expectedRevision: nil)
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet, bypassQuietHours: bypass), expectedRevision: 1)
  #expect(throws: CoreError.invalidDate) { _ = try store.desiredSystemNotifications(now: now.addingTimeInterval(-60)) }

  reminder.dueAt = StoreDates.maximum
  reminder.alertOffsets = [0]
  try store.save(reminder, expectedRevision: 1)
  if bypass {
    #expect(try store.desiredSystemNotifications(now: now).map(\.fireAt) == [StoreDates.maximum])
  } else {
    #expect(throws: CoreError.invalidDate) { _ = try store.desiredSystemNotifications(now: now) }
  }
}
