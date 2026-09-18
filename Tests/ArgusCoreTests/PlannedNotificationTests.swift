import Foundation
import Testing

@testable import ArgusCore

struct PlannedNotificationTests {
  func d(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
  func item(_ due: String, offsets: [TimeInterval] = [0], recurrence: RecurrenceRule? = nil) throws
    -> Reminder
  {
    try Reminder(
      title: "Work", dueAt: d(due), timeZoneID: "UTC", createdAt: d("2026-09-01T00:00:00Z"),
      updatedAt: d("2026-09-01T00:00:00Z"), alertOffsets: offsets, recurrence: recurrence)
  }

  @Test func coalescedOffsetsRetainOneOriginalOccurrence() throws {
    let reminder = try item("2026-09-21T06:30:00Z", offsets: [0, 3600])
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    let plans = try ScheduleCalculator.plannedNotifications(
      for: reminder, now: d("2026-09-21T00:00:00Z"), horizon: d("2026-09-21T08:00:00Z"),
      quietHours: quiet)
    #expect(plans.count == 1)
    let plan = try #require(plans.first)
    #expect(plan.intent.fireAt == d("2026-09-21T07:00:00Z"))
    #expect(plan.occurrenceDates == [reminder.dueAt])
  }

  @Test func coalescedRecurringOccurrencesKeepBothOriginalDates() throws {
    let reminder = try item(
      "2026-09-21T08:30:00Z", offsets: [0, 86400], recurrence: .weekdays(hour: 8, minute: 30))
    let quiet = try QuietHours(
      startHour: 0, startMinute: 0, endHour: 9, endMinute: 0, timeZoneID: "UTC")
    let plans = try ScheduleCalculator.plannedNotifications(
      for: reminder, now: d("2026-09-21T00:00:00Z"), horizon: d("2026-09-21T09:00:00Z"),
      quietHours: quiet)
    #expect(plans.count == 1)
    let plan = try #require(plans.first)
    #expect(plan.intent.fireAt == d("2026-09-21T09:00:00Z"))
    #expect(plan.occurrenceDates == [d("2026-09-21T08:30:00Z"), d("2026-09-22T08:30:00Z")])
    #expect(
      try JSONDecoder().decode([PlannedNotification].self, from: JSONEncoder().encode(plans))
        == plans)
  }

  @Test func snoozeProvenanceUsesDurableTargetOrLegacyAnchor() throws {
    var reminder = try item("2026-09-18T08:30:00Z", recurrence: .weekdays(hour: 8, minute: 30))
    reminder.snoozedUntil = d("2026-09-21T09:00:00Z")
    reminder.snoozedOccurrenceAt = d("2026-09-21T08:30:00Z")
    let plans = try ScheduleCalculator.plannedNotifications(
      for: reminder, now: d("2026-09-21T08:00:00Z"), horizon: d("2026-09-21T10:00:00Z"))
    #expect(plans.count == 1)
    #expect(try #require(plans.first).occurrenceDates == [d("2026-09-21T08:30:00Z")])
    reminder.recurrence = nil
    reminder.snoozedOccurrenceAt = nil
    let legacy = try ScheduleCalculator.plannedNotifications(
      for: reminder, now: d("2026-09-21T08:00:00Z"), horizon: d("2026-09-21T10:00:00Z"))
    #expect(try #require(legacy.first).occurrenceDates == [reminder.dueAt])
  }

  @Test func notificationAPIIsExactlyTheIntentProjection() throws {
    let reminder = try item(
      "2026-09-21T08:30:00Z", offsets: [0, 3600, 86400], recurrence: .weekdays(hour: 8, minute: 30))
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 9, endMinute: 0, timeZoneID: "UTC")
    for bypass in [false, true] {
      let now = d("2026-09-21T00:00:00Z")
      let horizon = d("2026-09-23T10:00:00Z")
      let plans = try ScheduleCalculator.plannedNotifications(
        for: reminder, now: now, horizon: horizon, quietHours: quiet, bypassQuietHours: bypass)
      let intents = try ScheduleCalculator.notifications(
        for: reminder, now: now, horizon: horizon, quietHours: quiet, bypassQuietHours: bypass)
      #expect(plans.map(\.intent) == intents)
      #expect(
        plans.allSatisfy {
          !$0.occurrenceDates.isEmpty && $0.occurrenceDates == Set($0.occurrenceDates).sorted()
        })
    }
  }
}

extension PlannedNotificationTests {
  @Test func inclusiveWindowIncludesFirstAndEndWhileDefaultExcludesStart() throws {
    let reminder = try item("2026-09-18T08:30:00Z", recurrence: .weekdays(hour: 8, minute: 30))
    let start = d("2026-09-21T08:30:00Z")
    let end = d("2026-09-22T08:30:00Z")
    #expect(
      try ScheduleCalculator.plannedNotifications(
        for: reminder, now: start, horizon: end, includingStart: true
      ).map(\.intent.fireAt) == [start, end])
    #expect(
      try ScheduleCalculator.plannedNotifications(for: reminder, now: start, horizon: end).map(
        \.intent.fireAt) == [end])
    #expect(
      try ScheduleCalculator.notifications(for: reminder, now: start, horizon: end).map(\.fireAt)
        == [end])
  }
  @Test func inclusivePointWindowCanCaptureOneAlert() throws {
    let reminder = try item("2026-09-21T08:30:00Z")
    #expect(
      try ScheduleCalculator.plannedNotifications(
        for: reminder, now: reminder.dueAt, horizon: reminder.dueAt, includingStart: true
      ).map(\.intent.fireAt) == [reminder.dueAt])
    #expect(
      try ScheduleCalculator.plannedNotifications(
        for: reminder, now: reminder.dueAt, horizon: reminder.dueAt
      ).isEmpty)
  }
  @Test func inclusiveCaptureWorksAtMinimumSupportedDate() throws {
    let minimum = Date(timeIntervalSince1970: -62_135_596_800)
    let reminder = try Reminder(
      title: "Boundary", dueAt: minimum, timeZoneID: "UTC", createdAt: minimum, updatedAt: minimum)
    let plans = try ScheduleCalculator.plannedNotifications(
      for: reminder, now: minimum, horizon: minimum, includingStart: true)
    #expect(plans.count == 1)
    #expect(try #require(plans.first).intent.fireAt == minimum)
    #expect(try #require(plans.first).occurrenceDates == [minimum])
  }
}
