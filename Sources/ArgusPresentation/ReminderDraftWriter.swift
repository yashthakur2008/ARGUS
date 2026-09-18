import ArgusCore
import ArgusStore

protocol ReminderDraftWriting: Sendable {
  func save(_ reminder: Reminder, expectedRevision: Int64?) async throws
}

/// Only editor draft persistence is isolated here. Other mutations and store open
/// remain synchronous and may still wait for the store lock on their caller.
actor ReminderDraftWriter: ReminderDraftWriting {
  private let store: ReminderStore
  init(store: ReminderStore) { self.store = store }

  func save(_ reminder: Reminder, expectedRevision: Int64?) throws {
    try store.save(reminder, expectedRevision: expectedRevision)
  }
}
