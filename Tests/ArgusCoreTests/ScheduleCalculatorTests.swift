import Foundation
import Testing

@testable import ArgusCore

struct ScheduleCalculatorTests {
  func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
  func reminder(
    _ due: String = "2026-09-21T15:30:00Z", offsets: [TimeInterval] = [0],
    recurrence: RecurrenceRule? = nil, zone: String = "America/Los_Angeles"
  ) throws -> Reminder {
    try Reminder(
      title: "Work", dueAt: date(due), timeZoneID: zone, createdAt: date("2026-09-01T00:00:00Z"),
      updatedAt: date("2026-09-01T00:00:00Z"), alertOffsets: offsets, recurrence: recurrence)
  }
  @Test func testOffsetsStableUniqueAndBounded() throws {
    let item = try reminder(offsets: [86400, 3600, 3600, 0])
    let now = date("2026-09-20T15:30:00Z")
    let horizon = item.dueAt
    let result = try ScheduleCalculator.notifications(for: item, now: now, horizon: horizon)
    #expect(result.map(\.fireAt) == [date("2026-09-21T14:30:00Z"), item.dueAt])
    #expect(Set(result.map(\.id)).count == 2)
    #expect(
      result.allSatisfy {
        $0.id.hasPrefix("argus.reminder.") && $0.reminderID == item.id && $0.sourceRevision == 1
      })
    #expect(try ScheduleCalculator.notifications(for: item, now: now, horizon: horizon) == result)
    var edited = item
    edited.revision = 2
    edited.title = "Edited"
    #expect(
      try ScheduleCalculator.notifications(for: edited, now: now, horizon: horizon).map(\.id)
        == result.map(\.id))
  }
  @Test func testSnoozeReplacesAlertsWithoutMovingDeadline() throws {
    var item = try reminder(offsets: [3600, 0])
    let deadline = item.dueAt
    item.snoozedUntil = deadline.addingTimeInterval(600)
    let result = try ScheduleCalculator.notifications(
      for: item, now: deadline.addingTimeInterval(-7200), horizon: deadline.addingTimeInterval(1200)
    )
    #expect(result.map(\.fireAt) == [item.snoozedUntil!])
    #expect(item.dueAt == deadline)
    item.isCompleted = true
    #expect(
      try ScheduleCalculator.notifications(
        for: item, now: deadline, horizon: deadline.addingTimeInterval(1200)) == [])
  }
  @Test func testWeekdaysSkipWeekendAndIncludeAdvanceAlertsBeyondHorizonDeadline() throws {
    let item = try reminder(
      "2026-09-18T15:30:00Z", offsets: [0, 86400], recurrence: .weekdays(hour: 8, minute: 30))
    let result = try ScheduleCalculator.notifications(
      for: item, now: date("2026-09-18T15:30:00Z"), horizon: date("2026-09-21T15:30:00Z"))
    #expect(result.map(\.fireAt) == [date("2026-09-20T15:30:00Z"), date("2026-09-21T15:30:00Z")])
  }
  @Test func testLimitIsVisibleAndInvalidHorizonRejected() throws {
    let item = try reminder(recurrence: .weekdays(hour: 8, minute: 30))
    #expect(throws: CoreError.notificationLimitExceeded) {
      try ScheduleCalculator.notifications(
        for: item, now: date("2026-09-01T00:00:00Z"), horizon: date("2027-09-01T00:00:00Z"))
    }
    #expect(throws: (any Error).self) {
      try ScheduleCalculator.notifications(
        for: item, now: item.dueAt, horizon: item.dueAt.addingTimeInterval(-1))
    }
    #expect(throws: (any Error).self) {
      try ScheduleCalculator.notifications(
        for: item, now: item.dueAt, horizon: Date(timeIntervalSince1970: .infinity))
    }
  }
  @Test func testWeekdaySpringGapAndFallFoldInCairo() throws {
    let zone = TimeZone(identifier: "Africa/Cairo")!
    // Cairo advances at Friday midnight, so 00:30 becomes the next valid time, 01:00.
    let spring = try RecurrenceRule.weekdays(hour: 0, minute: 30).nextOccurrence(
      after: date("2026-04-23T20:00:00Z"), timeZone: zone)
    #expect(spring == date("2026-04-23T22:00:00Z"))
    let rule = RecurrenceRule.weekdays(hour: 23, minute: 30)
    let first = try rule.nextOccurrence(after: date("2026-10-29T18:00:00Z"), timeZone: zone)
    #expect(first == date("2026-10-29T20:30:00Z"))
    #expect(try rule.nextOccurrence(after: first, timeZone: zone) == date("2026-10-30T21:30:00Z"))
  }
  @Test func testQuietHoursPlanningAndExplicitBypass() throws {
    let item = try reminder("2026-09-21T06:30:00Z", offsets: [0, 3600])
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: item.timeZoneID)
    let now = date("2026-09-21T00:00:00Z")
    let horizon = date("2026-09-21T15:00:00Z")
    #expect(
      try ScheduleCalculator.notifications(for: item, now: now, horizon: horizon, quietHours: quiet)
        .map(\.fireAt) == [date("2026-09-21T14:00:00Z")])
    #expect(
      try ScheduleCalculator.notifications(
        for: item, now: now, horizon: horizon, quietHours: quiet, bypassQuietHours: true
      ).count == 2)
    #expect(
      try ScheduleCalculator.notifications(
        for: item, now: now, horizon: item.dueAt, quietHours: quiet) == [])
  }
}

extension ScheduleCalculatorTests {
  @Test func testLegacyRecurringSnoozeTargetsOriginalAnchor() throws {
    var item = try reminder("2026-09-21T15:30:00Z", recurrence: .weekdays(hour: 8, minute: 30))
    item.snoozedUntil = date("2026-09-21T16:00:00Z")
    let result = try ScheduleCalculator.notifications(
      for: item, now: date("2026-09-21T14:00:00Z"), horizon: date("2026-09-22T15:30:00Z"))
    #expect(result.map(\.fireAt) == [date("2026-09-21T16:00:00Z"), date("2026-09-22T15:30:00Z")])
    #expect(
      try JSONDecoder().decode([NotificationIntent].self, from: JSONEncoder().encode(result))
        == result)
  }
  @Test func testFoldProducesOneNotificationForLocalOccurrence() throws {
    let item = try reminder(
      "2026-10-28T20:30:00Z", recurrence: .weekdays(hour: 23, minute: 30), zone: "Africa/Cairo")
    let result = try ScheduleCalculator.notifications(
      for: item, now: date("2026-10-29T18:00:00Z"), horizon: date("2026-10-29T22:00:00Z"))
    #expect(result.map(\.fireAt) == [date("2026-10-29T20:30:00Z")])
  }
  @Test func testEmptyOffsetsAndEqualHorizonProduceNone() throws {
    let item = try reminder(offsets: [])
    #expect(
      try ScheduleCalculator.notifications(for: item, now: item.createdAt, horizon: item.dueAt)
        == [])
    #expect(
      try ScheduleCalculator.notifications(for: item, now: item.dueAt, horizon: item.dueAt) == [])
  }
}

extension ScheduleCalculatorTests {
  @Test func testRestartPreservesOneTimeQuietHoursDeferral() throws {
    let item = try reminder("2026-09-21T01:00:00Z", zone: "UTC")
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 8, endMinute: 0, timeZoneID: "UTC")
    let result = try ScheduleCalculator.notifications(
      for: item, now: date("2026-09-21T07:00:00Z"), horizon: date("2026-09-21T09:00:00Z"),
      quietHours: quiet)
    #expect(result.map(\.fireAt) == [date("2026-09-21T08:00:00Z")])
    #expect(item.dueAt == date("2026-09-21T01:00:00Z"))
  }
  @Test func testRestartPreservesRecurringQuietHoursDeferral() throws {
    let item = try reminder(
      "2026-09-18T01:00:00Z", recurrence: .weekdays(hour: 1, minute: 0), zone: "UTC")
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 8, endMinute: 0, timeZoneID: "UTC")
    let result = try ScheduleCalculator.notifications(
      for: item, now: date("2026-09-21T07:00:00Z"), horizon: date("2026-09-21T09:00:00Z"),
      quietHours: quiet)
    #expect(result.map(\.fireAt) == [date("2026-09-21T08:00:00Z")])
  }
}

extension ScheduleCalculatorTests {
  @Test func testExactly64NotificationsAreAllowed() throws {
    let item = try reminder(recurrence: .weekdays(hour: 8, minute: 30))
    let now = date("2026-09-21T00:00:00Z")
    #expect(
      try ScheduleCalculator.notifications(
        for: item, now: now, horizon: date("2026-12-17T16:30:00Z")
      ).count == 64)
    #expect(throws: CoreError.notificationLimitExceeded) {
      try ScheduleCalculator.notifications(
        for: item, now: now, horizon: date("2026-12-18T16:30:00Z"))
    }
  }
}

extension ScheduleCalculatorTests {
  @Test func testRestartBetweenFoldInstantsNeverPlansSecondOccurrence() throws {
    let item = try reminder(
      "2026-10-28T20:30:00Z", recurrence: .weekdays(hour: 23, minute: 30), zone: "Africa/Cairo")
    let now = date("2026-10-29T20:45:00Z")
    #expect(
      try ScheduleCalculator.notifications(
        for: item, now: now, horizon: date("2026-10-29T22:00:00Z")
      ).isEmpty)
    #expect(
      try item.recurrence!.nextOccurrence(
        after: now, timeZone: TimeZone(identifier: "Africa/Cairo")!) == date("2026-10-30T21:30:00Z")
    )
  }
}

extension ScheduleCalculatorTests {
  @Test func testLaterRecurringSnoozeSurvivesDecodeRenameAndReplanning() throws {
    var item = try reminder(
      "2026-09-18T08:30:00Z", offsets: [0, 3600], recurrence: .weekdays(hour: 8, minute: 30),
      zone: "UTC")
    item.snoozedUntil = date("2026-09-21T09:00:00Z")
    // Persist the explicit occurrence identity, not the mutable record update timestamp.
    var payload =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as! [String: Any]
    payload["snoozedOccurrenceAt"] = date("2026-09-21T08:30:00Z").timeIntervalSinceReferenceDate
    var restored = try JSONDecoder().decode(
      Reminder.self, from: JSONSerialization.data(withJSONObject: payload))
    restored.title = "Renamed after snooze"
    restored.updatedAt = date("2026-09-21T06:50:00Z")
    let deadline = restored.dueAt
    let horizon = date("2026-09-22T09:00:00Z")
    let expected = [
      date("2026-09-21T09:00:00Z"), date("2026-09-22T07:30:00Z"), date("2026-09-22T08:30:00Z"),
    ]
    #expect(
      try ScheduleCalculator.notifications(
        for: restored, now: date("2026-09-21T07:00:00Z"), horizon: horizon
      ).map(\.fireAt) == expected)
    #expect(
      try ScheduleCalculator.notifications(
        for: restored, now: date("2026-09-21T08:00:00Z"), horizon: horizon
      ).map(\.fireAt) == expected)
    restored.updatedAt = date("2026-09-22T06:00:00Z")
    #expect(
      try ScheduleCalculator.notifications(
        for: restored, now: date("2026-09-22T06:00:00Z"), horizon: horizon
      ).map(\.fireAt) == Array(expected.dropFirst()))
    #expect(restored.dueAt == deadline)
    let saved =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored)) as! [String: Any]
    #expect(
      saved["snoozedOccurrenceAt"] as? Double
        == date("2026-09-21T08:30:00Z").timeIntervalSinceReferenceDate)
  }
}
