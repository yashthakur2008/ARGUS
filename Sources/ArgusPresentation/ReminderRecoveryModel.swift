import Foundation
import Observation
import ArgusCore
import ArgusStore

@MainActor @Observable
public final class ReminderRecoveryModel {
  public private(set) var notices: [ReminderNotice] = []
  public private(set) var policy: NotificationPolicy?
  public private(set) var issue: String?
  private let store: ReminderStore
  public init(store: ReminderStore) { self.store = store }
  public var activeNotices: [ReminderNotice] { notices.filter { $0.dismissedAt == nil } }
  public var attentionCount: Int { Set(activeNotices.map(\.reminderID)).count }
  public func refresh(now: Date) throws {
    _ = try store.captureDueNotices(now: now)
    let loadedNotices = try store.notices(includeDismissed: true)
    let loadedPolicy = try store.notificationPolicy()
    notices = loadedNotices
    policy = loadedPolicy
  }
  public func open(_ notice: ReminderNotice) -> Reminder? {
    do {
      guard let reminder = try store.reminder(id: notice.reminderID) else {
        issue = "This reminder no longer exists. Its source cannot be opened."
        return nil
      }
      issue = nil
      return reminder
    } catch { issue = "Could not open the reminder: \(error)"; return nil }
  }

  @discardableResult public func dismiss(_ notice: ReminderNotice, now: Date) -> Bool {
    do {
      try store.dismissNotice(id: notice.id, now: now)
      notices = try store.notices(includeDismissed: true)
      issue = nil
      return true
    } catch { issue = "Could not dismiss this notice: \(error)"; return false }
  }

  @discardableResult public func snooze(_ notice: ReminderNotice, occurrenceAt: Date?, until: Date,
    expectedRevision: Int64, now: Date) -> Bool {
    let selected = occurrenceAt ?? (notice.occurrenceDates.count == 1 ? notice.occurrenceDates.first : nil)
    guard let selected, notice.occurrenceDates.contains(selected) else {
      issue = "Choose the exact occurrence to snooze, or open the source reminder."
      return false
    }
    do {
      try store.snoozeNotice(id: notice.id, occurrenceAt: selected, until: until,
        expectedRevision: expectedRevision, now: now)
      notices = try store.notices(includeDismissed: true)
      issue = nil
      return true
    } catch { issue = "Could not snooze this notice. Please review the current reminder. \(error)"; return false }
  }

  @discardableResult public func savePolicy(_ policy: NotificationPolicy, expectedRevision: Int64) -> Bool {
    do {
      try store.saveNotificationPolicy(policy, expectedRevision: expectedRevision)
      self.policy = try store.notificationPolicy()
      issue = nil
      return true
    } catch { issue = "Could not save notification settings. Reload and review the current policy. \(error)"; return false }
  }
}
