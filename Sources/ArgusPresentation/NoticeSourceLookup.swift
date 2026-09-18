import ArgusCore
import ArgusStore

public enum NoticeSourceLookupResult: Equatable, Sendable {
  case found(Reminder), missing, failed(String)
}

protocol NoticeSourceLookingUp: Sendable {
  func lookup(_ notice: ReminderNotice) async -> NoticeSourceLookupResult
}

actor NoticeSourceLookup: NoticeSourceLookingUp {
  private let store: ReminderStore
  init(store: ReminderStore) { self.store = store }
  func lookup(_ notice: ReminderNotice) -> NoticeSourceLookupResult {
    do {
      guard let source = try store.reminder(id: notice.reminderID) else { return .missing }
      return .found(source)
    } catch { return .failed("Could not open the reminder: \(error)") }
  }
}
