import Foundation
import Testing
import ArgusCore
@testable import ArgusPresentation

struct ReminderTimelineTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func item(_ offset: TimeInterval) throws -> Reminder {
    try Reminder(title: "Fixture", dueAt: now.addingTimeInterval(offset), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  }
  @Test func overdueVisibleAndSectionBoundaries() throws {
    let overdue = try item(-3600), soon = try item(3600), later = try item(3601), outside = try item(7 * 86400 + 1)
    #expect(try ReminderTimeline.nowItems([later, overdue, outside, soon], now: now).map(\.id) == [overdue.id, soon.id])
    #expect(try ReminderTimeline.approachingItems([later, overdue, outside, soon], now: now).map(\.id) == [later.id])
  }
  @Test func recurringItemShowsNextOccurrenceNotAncientDeadline() throws {
    var reminder = try item(-30 * 86400)
    reminder.recurrence = .weekdays(hour: 10, minute: 0)
    let date = try ReminderTimeline.displayDate(for: reminder, now: now)
    #expect(date > now)
    #expect(date < now.addingTimeInterval(4 * 86400))
    #expect(try ReminderTimeline.nowItems([reminder], now: now).isEmpty)
  }
  @Test func snoozeIsVisibleWithoutDeadlineMutation() throws {
    var reminder = try item(-3600)
    reminder.snoozedUntil = now.addingTimeInterval(7200)
    #expect(try ReminderTimeline.displayDate(for: reminder, now: now) == reminder.snoozedUntil)
    #expect(try ReminderTimeline.approachingItems([reminder], now: now).count == 1)
  }
}
extension ReminderTimelineTests {
  @Test func todaysRecurringOverdueOccurrenceRemainsVisible() throws {
    var reminder = try item(-7 * 86400)
    reminder.recurrence = .weekdays(hour: 8, minute: 0)
    let later = now.addingTimeInterval(3600)
    #expect(try ReminderTimeline.displayDate(for: reminder, now: later) == now)
    #expect(try ReminderTimeline.nowItems([reminder], now: later).count == 1)
  }
}
extension ReminderTimelineTests {
  @Test func longSnoozeDoesNotHideOtherRecurringOccurrences() throws {
    let formatter = ISO8601DateFormatter()
    let monday = formatter.date(from: "2026-09-21T08:30:00Z")!
    let tuesday = formatter.date(from: "2026-09-22T08:00:00Z")!
    let friday = formatter.date(from: "2026-09-25T09:00:00Z")!
    let item = try Reminder(title: "Long snooze", dueAt: monday, timeZoneID: "UTC", createdAt: monday, updatedAt: monday, recurrence: .weekdays(hour: 8, minute: 30), snoozedUntil: friday, snoozedOccurrenceAt: monday)
    let intents = try ScheduleCalculator.notifications(for: item, now: tuesday, horizon: tuesday.addingTimeInterval(3600))
    #expect(try ReminderTimeline.displayDate(for: item, now: tuesday) == intents.first?.fireAt)
    #expect(try ReminderTimeline.nowItems([item], now: tuesday).count == 1)
    #expect(try ReminderTimeline.approachingItems([item], now: tuesday).isEmpty)
  }
}
