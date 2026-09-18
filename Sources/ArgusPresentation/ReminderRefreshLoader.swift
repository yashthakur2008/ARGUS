import Foundation
import ArgusCore
import ArgusStore

enum ReminderRefreshLoadResult: Sendable {
  case listFailure(String)
  // This preliminary list is a repair fallback, not part of a successful coherent snapshot.
  case recoveryFailure(reminders: [Reminder], message: String)
  case loaded(reminders: [Reminder], notices: [ReminderNotice], policy: NotificationPolicy)
}

protocol ReminderRefreshLoading: Sendable {
  func load(now: Date, sequence: Int) async -> ReminderRefreshLoadResult
}

/// One active I/O load and at most one latest follow-up, shared by pending callers.
/// Cancellation of one waiting caller does not cancel work shared by other callers.
/// Request sequences belong to one AppModel, not actor arrival order or wall time.
/// Only refresh is off-MainActor: synchronous mutation/open APIs may still wait for
/// the shared store lock. This is not general nonblocking storage isolation.
actor ReminderRefreshLoader: ReminderRefreshLoading {
  private let worker: any ReminderRefreshLoading
  private var active: Task<ReminderRefreshLoadResult, Never>?
  private var activeSequence: Int?
  private var pending: Task<ReminderRefreshLoadResult, Never>?
  private var pendingNow: Date?
  private var pendingSequence: Int?

  init(store: ReminderStore) { worker = SQLiteRefreshWorker(store: store) }
  init(worker: any ReminderRefreshLoading) { self.worker = worker }

  func load(now: Date, sequence: Int) async -> ReminderRefreshLoadResult { await enqueue(now: now, sequence: sequence).value }

  /// Returns the shared completion for this request's group, without waiting for I/O.
  func enqueue(now: Date, sequence: Int) -> Task<ReminderRefreshLoadResult, Never> {
    if let pending {
      if sequence > pendingSequence! {
        pendingNow = now
        pendingSequence = sequence
      }
      return pending
    }
    if let active {
      if sequence <= activeSequence! { return active }
      pendingNow = now
      pendingSequence = sequence
      let followup = Task {
        _ = await active.value
        return await self.startPending().value
      }
      pending = followup
      return followup
    }
    return start(now: now, sequence: sequence)
  }

  private func startPending() -> Task<ReminderRefreshLoadResult, Never> {
    // Only the single pending task invokes this, after its active predecessor finishes.
    let now = pendingNow!
    let sequence = pendingSequence!
    pending = nil
    pendingNow = nil
    pendingSequence = nil
    return start(now: now, sequence: sequence)
  }

  private func start(now: Date, sequence: Int) -> Task<ReminderRefreshLoadResult, Never> {
    let task = Task {
      await worker.load(now: now, sequence: sequence)
    }
    // Retain this single completed task too: late older callers share its result
    // rather than starting obsolete I/O. Sequences are scoped to one AppModel.
    active = task
    activeSequence = sequence
    return task
  }
}

/// Synchronous SQLite work stays on this separate actor, never the MainActor.
private actor SQLiteRefreshWorker: ReminderRefreshLoading {
  let store: ReminderStore
  init(store: ReminderStore) { self.store = store }

  func load(now: Date, sequence: Int) -> ReminderRefreshLoadResult {
    let reminders: [Reminder]
    do { reminders = try store.list() }
    catch { return .listFailure(String(describing: error)) }
    do {
      let snapshot = try store.refreshSnapshot(now: now)
      return .loaded(reminders: snapshot.reminders, notices: snapshot.notices, policy: snapshot.policy)
    } catch {
      return .recoveryFailure(reminders: reminders, message: String(describing: error))
    }
  }
}
