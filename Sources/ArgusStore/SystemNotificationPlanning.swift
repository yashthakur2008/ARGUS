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
            // A one-time snooze replaces every original offset, including an empty list.
            let candidates = reminder.snoozedUntil.map { [$0] }
              ?? reminder.alertOffsets.map { reminder.dueAt.addingTimeInterval(-$0) }
            // Validate raw arithmetic before handing any candidate to Calendar policy work.
            for candidate in candidates { try StoreDates.validate(candidate) }
            let allowed = try candidates.map { candidate in
              let fireAt = policy.bypassQuietHours ? candidate
                : policy.quietHours?.nextAllowedDate(for: candidate) ?? candidate
              try StoreDates.validate(fireAt)
              return fireAt
            }
            // Deferral is not monotone across DST folds: an advance alert can fire last.
            horizon = max(now, allowed.max() ?? now)
          }
          return try ScheduleCalculator.notifications(for: reminder, now: now, horizon: horizon,
            quietHours: policy.quietHours, bypassQuietHours: policy.bypassQuietHours)
        }.sorted(by: notificationOrder)
      }
    }
  }
}
