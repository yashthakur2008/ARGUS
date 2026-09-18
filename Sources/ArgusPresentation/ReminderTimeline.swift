import Foundation
import ArgusCore

public enum ReminderTimeline {
  public static func displayDate(for reminder: Reminder, now: Date) throws -> Date {
    guard let recurrence = reminder.recurrence else { return reminder.snoozedUntil ?? reminder.dueAt }
    var unsnoozed = reminder
    unsnoozed.snoozedUntil = nil
    unsnoozed.snoozedOccurrenceAt = nil
    let occurrence = try unsnoozed.occurrenceToSnooze(at: now)
    guard let snoozed = reminder.snoozedUntil else { return occurrence }
    let target = reminder.snoozedOccurrenceAt ?? reminder.dueAt
    if occurrence == target {
      guard let zone = TimeZone(identifier: reminder.timeZoneID) else { throw CoreError.invalidTimeZone(reminder.timeZoneID) }
      return min(snoozed, try recurrence.nextOccurrence(after: occurrence, timeZone: zone))
    }
    return snoozed > now ? min(occurrence, snoozed) : occurrence
  }

  public static func nowItems(_ reminders: [Reminder], now: Date) throws -> [Reminder] {
    try sorted(reminders, now: now).filter { try displayDate(for: $0, now: now) <= now.addingTimeInterval(3600) }
  }
  public static func approachingItems(_ reminders: [Reminder], now: Date) throws -> [Reminder] {
    try sorted(reminders, now: now).filter {
      let date = try displayDate(for: $0, now: now)
      return date > now.addingTimeInterval(3600) && date <= now.addingTimeInterval(7 * 86400)
    }
  }
  public static func sorted(_ reminders: [Reminder], now: Date) throws -> [Reminder] {
    let active = reminders.filter { !$0.isCompleted }
    let dated: [(reminder: Reminder, date: Date)] = try active.map {
      (reminder: $0, date: try displayDate(for: $0, now: now))
    }
    let ordered = dated.sorted { left, right in
      if left.date == right.date { return left.reminder.id.uuidString < right.reminder.id.uuidString }
      return left.date < right.date
    }
    return ordered.map { $0.reminder }
  }
}
