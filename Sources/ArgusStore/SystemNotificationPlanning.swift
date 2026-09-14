import Foundation
import ArgusCore

extension ReminderStore {
  /// All finite future one-time alerts, but only the next seven elapsed days of recurrence.
  /// This explicit API does not change the caller-bounded desiredNotifications contract.
  public func desiredSystemNotifications(now: Date) throws -> [NotificationIntent] {
    try StoreDates.validate(now)
    return try lock.withLock {
      try database.transaction(write: false) {
        let policy = try database.readPolicy()
        return try database.readReminders().flatMap { reminder -> [NotificationIntent] in
          guard !reminder.isCompleted else { return [] }
          let horizon: Date
          if reminder.recurrence != nil {
            horizon = min(StoreDates.maximum, now.addingTimeInterval(StoreDates.week))
          } else {
            let lastCandidate = reminder.snoozedUntil ?? reminder.dueAt
            let lastAllowed = policy.bypassQuietHours ? lastCandidate
              : policy.quietHours?.nextAllowedDate(for: lastCandidate) ?? lastCandidate
            try StoreDates.validate(lastAllowed)
            horizon = max(now, lastAllowed)
          }
          return try ScheduleCalculator.notifications(for: reminder, now: now, horizon: horizon,
            quietHours: policy.quietHours, bypassQuietHours: policy.bypassQuietHours)
        }.sorted(by: notificationOrder)
      }
    }
  }
}
