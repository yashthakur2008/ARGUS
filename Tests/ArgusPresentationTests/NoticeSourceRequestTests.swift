import Foundation
import Testing
import ArgusCore
@testable import ArgusStore
@testable import ArgusPresentation

// Tests target the production-used owner, not a copied reducer.
@MainActor struct NoticeSourceRequestTests {
  @Test(arguments: [false, true])
  func cancelledRequestRetainsSlotUntilDrainAndCannotRearm(failure: Bool) async throws {
    let (source, notice) = try fixture()
    let gate = SourceGate()
    let owner = NoticeSourceRequest(lookup: { await gate.read($0) })
    owner.activate()
    let firstRequest = owner.start(notice: notice, action: .edit, currentVisibleNotices: { [notice] })
    let first = try #require(firstRequest)
    await gate.waitUntilEntered()
    owner.deactivate()
    owner.activate()
    #expect(owner.isLoading)
    let rejected = owner.start(notice: notice, action: .snooze, currentVisibleNotices: { [notice] })
    #expect(rejected == nil)
    #expect(await gate.count == 1)
    await gate.finish(failure ? .failed("obsolete error") : .found(source))
    await first.value
    #expect(!owner.isLoading)
    #expect(owner.destination == nil)
    #expect(owner.issue == nil)
    let nextRequest = owner.start(notice: notice, action: .snooze, currentVisibleNotices: { [notice] })
    let next = try #require(nextRequest)
    await gate.waitUntilEntered()
    await gate.finish(.found(source))
    await next.value
    #expect(owner.destination?.action == .snooze)
    #expect(owner.destination?.notice == notice)
    #expect(owner.destination?.source == source)
  }

  @Test func acceptedDestinationSurvivesPendingContextInvalidation() async throws {
    let (source, notice) = try fixture()
    let owner = NoticeSourceRequest(lookup: { _ in .found(source) })
    owner.activate()
    let taskRequest = owner.start(notice: notice, action: .edit, currentVisibleNotices: { [notice] })
    let task = try #require(taskRequest)
    await task.value
    let destination = try #require(owner.destination)
    owner.invalidatePending()
    owner.deactivate()
    owner.activate()
    #expect(owner.destination?.id == destination.id)
    #expect(owner.destination?.source == source)
    let rejected = owner.start(notice: notice, action: .snooze, currentVisibleNotices: { [notice] })
    #expect(rejected == nil)
    owner.destination = nil // Actual sheet binding's explicit dismissal.
    #expect(owner.destination == nil)
  }

  @Test(arguments: [false, true], [false, true])
  func pendingInvalidationOrVisibleRemovalSuppressesResult(invalidate: Bool, failure: Bool) async throws {
    let (source, notice) = try fixture()
    let gate = SourceGate()
    let owner = NoticeSourceRequest(lookup: { await gate.read($0) })
    owner.activate()
    let visible = VisibleNotices([notice])
    let taskRequest = owner.start(notice: notice, action: .edit, currentVisibleNotices: { visible.notices })
    let task = try #require(taskRequest)
    await gate.waitUntilEntered()
    if invalidate { owner.invalidatePending() } else { visible.notices = [] }
    #expect(owner.isLoading)
    await gate.finish(failure ? .failed("obsolete") : .found(source))
    await task.value
    #expect(owner.destination == nil)
    #expect(owner.issue == nil)
    #expect(!owner.isLoading)
  }

  @Test func busyRepeatCannotChangeAcceptedAction() async throws {
    let (source, notice) = try fixture()
    let gate = SourceGate()
    let owner = NoticeSourceRequest(lookup: { await gate.read($0) })
    owner.activate()
    let taskRequest = owner.start(notice: notice, action: .edit, currentVisibleNotices: { [notice] })
    let task = try #require(taskRequest)
    await gate.waitUntilEntered()
    for _ in 0..<100 {
      let repeated = owner.start(notice: notice, action: .snooze, currentVisibleNotices: { [notice] })
      #expect(repeated == nil)
    }
    #expect(await gate.count == 1)
    await gate.finish(.found(source))
    await task.value
    #expect(owner.destination?.action == .edit)
    #expect(owner.destination?.notice == notice)
  }

  @Test(arguments: [false, true])
  func acceptedMissingAndFailureAreRequestLocal(failure: Bool) async throws {
    let (_, notice) = try fixture()
    let owner = NoticeSourceRequest(lookup: { _ in failure ? .failed("request failure") : .missing })
    owner.activate()
    let taskRequest = owner.start(notice: notice, action: .edit, currentVisibleNotices: { [notice] })
    let task = try #require(taskRequest)
    await task.value
    #expect(owner.issue == (failure ? "request failure" : "This reminder no longer exists. Its source cannot be opened."))
    #expect(owner.destination == nil)
    owner.invalidatePending()
    #expect(owner.issue == nil)
  }

  @Test(arguments: [false, true])
  func completionCannotReplaceAnEstablishedDestination(failure: Bool) async throws {
    let (source, notice) = try fixture()
    let gate = SourceGate()
    let owner = NoticeSourceRequest(lookup: { await gate.read($0) })
    owner.activate()
    let request = owner.start(notice: notice, action: .edit, currentVisibleNotices: { [notice] })
    let task = try #require(request)
    await gate.waitUntilEntered()
    let established = NoticeSourceDestination(source: source, notice: notice, action: .snooze)
    owner.destination = established
    await gate.finish(failure ? .failed("late issue") : .found(source))
    await task.value
    #expect(owner.destination?.id == established.id)
    #expect(owner.issue == nil)
    #expect(!owner.isLoading)
  }

  @Test(arguments: [false, true])
  func changedFullNoticeSuppressesLateCompletion(failure: Bool) async throws {
    let (source, notice) = try fixture()
    let gate = SourceGate()
    let owner = NoticeSourceRequest(lookup: { await gate.read($0) })
    owner.activate()
    let visible = VisibleNotices([notice])
    let taskRequest = owner.start(notice: notice, action: .edit, currentVisibleNotices: { visible.notices })
    let task = try #require(taskRequest)
    await gate.waitUntilEntered()
    visible.notices = [ReminderNotice(id: notice.id, reminderID: notice.reminderID, titleSnapshot: notice.titleSnapshot,
      scheduledAt: notice.scheduledAt, sourceRevision: notice.sourceRevision, capturedAt: notice.capturedAt,
      occurrenceDates: notice.occurrenceDates, dismissedAt: notice.capturedAt)]
    // Intentionally no invalidation callback: acceptance itself must use full equality.
    await gate.finish(failure ? .failed("old error") : .found(source))
    await task.value
    #expect(owner.destination == nil)
    #expect(owner.issue == nil)
  }

  private func fixture() throws -> (Reminder, ReminderNotice) {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let source = try Reminder(title: "Source", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    return (source, ReminderNotice(id: "fixture", reminderID: source.id, titleSnapshot: source.title,
      scheduledAt: now, sourceRevision: source.revision, capturedAt: now,
      occurrenceDates: [now], dismissedAt: nil))
  }
}

private actor SourceGate {
  private(set) var count = 0
  private var pending: CheckedContinuation<NoticeSourceLookupResult, Never>?
  private var entered: CheckedContinuation<Void, Never>?
  func read(_ notice: ReminderNotice) async -> NoticeSourceLookupResult {
    count += 1
    return await withCheckedContinuation {
      pending = $0
      entered?.resume(); entered = nil
    }
  }
  func waitUntilEntered() async {
    if pending != nil { return }
    await withCheckedContinuation { entered = $0 }
  }
  func finish(_ result: NoticeSourceLookupResult) { pending?.resume(returning: result); pending = nil }
}

@MainActor private final class VisibleNotices {
  var notices: [ReminderNotice]
  init(_ notices: [ReminderNotice]) { self.notices = notices }
}
