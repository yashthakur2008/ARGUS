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
  private let sourceLookup: any NoticeSourceLookingUp
  @ObservationIgnored var onExplicitChange: (@MainActor () -> Void)?
  public convenience init(store: ReminderStore) {
    self.init(store: store, sourceLookup: NoticeSourceLookup(store: store))
  }
  init(store: ReminderStore, sourceLookup: any NoticeSourceLookingUp) {
    self.store = store
    self.sourceLookup = sourceLookup
  }

  /// A sampled request result, never a write to shared recovery issue state.
  /// Existing synchronous open remains available for API compatibility.
  public func lookupSource(_ notice: ReminderNotice) async -> NoticeSourceLookupResult {
    await sourceLookup.lookup(notice)
  }
  public var activeNotices: [ReminderNotice] { notices.filter { $0.dismissedAt == nil } }
  public var attentionCount: Int { Set(activeNotices.map(\.reminderID)).count }
  public func refresh(now: Date) throws {
    // Fence pending asynchronous publication even if capture commits but a later read fails.
    onExplicitChange?()
    _ = try store.captureDueNotices(now: now)
    let loadedNotices = try store.notices(includeDismissed: true)
    let loadedPolicy = try store.notificationPolicy()
    applyLoaded(notices: loadedNotices, policy: loadedPolicy)
  }

  func applyLoaded(notices: [ReminderNotice], policy: NotificationPolicy) {
    self.notices = notices
    self.policy = policy
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
      onExplicitChange?()
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
      onExplicitChange?()
      notices = try store.notices(includeDismissed: true)
      issue = nil
      return true
    } catch StoreError.activeSnoozeConflict {
      issue = "A different occurrence already has a pending snooze. Open the source reminder to review it. This notice was not dismissed."
      return false
    } catch { issue = "Could not snooze this notice. Please review the current reminder. \(error)"; return false }
  }

  @discardableResult public func savePolicy(_ policy: NotificationPolicy, expectedRevision: Int64) -> Bool {
    do {
      try store.saveNotificationPolicy(policy, expectedRevision: expectedRevision)
      onExplicitChange?()
      self.policy = try store.notificationPolicy()
      issue = nil
      return true
    } catch { issue = "Could not save notification settings. Reload and review the current policy. \(error)"; return false }
  }
}
