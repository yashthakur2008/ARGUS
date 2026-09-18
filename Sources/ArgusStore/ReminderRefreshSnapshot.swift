import Foundation
import ArgusCore

/// Coherent at transaction commit, not a promise that other connections never change afterward.
public struct ReminderRefreshSnapshot: Sendable {
  public let reminders: [Reminder]
  public let notices: [ReminderNotice]
  public let policy: NotificationPolicy
}

extension ReminderStore {
  public func refreshSnapshot(now: Date) throws -> ReminderRefreshSnapshot {
    try StoreDates.validate(now)
    return try lock.withLock {
      try database.transaction {
        _ = try captureDueNoticesLocked(now: now)
        return ReminderRefreshSnapshot(reminders: try database.readReminders(),
          notices: try database.readNotices(includeDismissed: true), policy: try database.readPolicy())
      }
    }
  }
}
