import Foundation
import Observation
import ArgusCore
import ArgusStore

enum NoticeSourceAction { case edit, snooze }

struct NoticeSourceDestination: Identifiable {
  let id = UUID()
  let source: Reminder
  let notice: ReminderNotice
  let action: NoticeSourceAction
}

/// View-lifetime owner. Cancellation suppresses publication, not a SQLite/NSLock
/// wait. Keep the single loading slot until the worker drains, even after cancel.
@MainActor @Observable
final class NoticeSourceRequest {
  var destination: NoticeSourceDestination?
  private(set) var issue: String?
  private(set) var isLoading = false
  private var active = false
  private var generation = 0
  @ObservationIgnored private var task: Task<Void, Never>?
  private let lookup: @MainActor (ReminderNotice) async -> NoticeSourceLookupResult

  init(lookup: @escaping @MainActor (ReminderNotice) async -> NoticeSourceLookupResult) {
    self.lookup = lookup
  }

  func activate() { active = true }
  func deactivate() { active = false; invalidatePending() }

  /// Never dismiss an accepted sheet or discard its draft on a context refresh.
  func invalidatePending() {
    generation += 1
    task?.cancel()
    issue = nil
  }

  @discardableResult
  func start(notice: ReminderNotice, action: NoticeSourceAction,
    currentVisibleNotices: @escaping @MainActor () -> [ReminderNotice]) -> Task<Void, Never>? {
    guard active, !isLoading, destination == nil else { return nil }
    generation += 1
    let token = generation
    issue = nil
    isLoading = true
    let request = Task { [self] in
      // Cleanup is owned by the only I/O request, not by its acceptance token.
      // Invalidating a token must not permanently occupy the loading slot.
      defer { isLoading = false; task = nil }
      let result = await lookup(notice)
      guard !Task.isCancelled, active, token == generation, destination == nil,
        currentVisibleNotices().contains(notice) else { return }
      switch result {
      case .found(let source):
        destination = NoticeSourceDestination(source: source, notice: notice, action: action)
      case .missing:
        issue = "This reminder no longer exists. Its source cannot be opened."
      case .failed(let message): issue = message
      }
    }
    task = request
    return request
  }
}
