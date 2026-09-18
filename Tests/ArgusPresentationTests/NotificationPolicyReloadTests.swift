import Foundation
import Testing
import ArgusCore
import ArgusPlatform
import ArgusStore
@testable import ArgusPresentation

@MainActor struct NotificationPolicyReloadTests {
  @Test(arguments: [false, true])
  func failedReloadDoesNotReturnRetainedPolicy(recoveryFailure: Bool) async throws {
    let old = try NotificationPolicy(revision: 1)
    let failure: ReminderRefreshLoadResult = recoveryFailure
      ? .recoveryFailure(reminders: [], message: "synthetic recovery failure")
      : .listFailure("synthetic list failure")
    let loader = PolicyReloadScript([.loaded(reminders: [], notices: [], policy: old), failure])
    let h = try PolicyReloadHarness(loader: loader)
    defer { h.cleanUp() }
    await h.model.refresh()
    #expect(h.model.recovery.policy == old)
    let outcome = await h.model.reloadNotificationPolicy()
    #expect(outcome == .failed)
    #expect(h.model.recovery.policy == old) // Cache survives, but is not claimed freshly loaded.
    #expect(await loader.count == 2) // Wrapper must not perform a second independent load.
  }

  @Test func successfulReloadReturnsPolicyFromThatRequest() async throws {
    let old = try NotificationPolicy(revision: 1)
    let updated = try NotificationPolicy(bypassQuietHours: true, revision: 2)
    let loader = PolicyReloadScript([
      .loaded(reminders: [], notices: [], policy: old),
      .loaded(reminders: [], notices: [], policy: updated),
    ])
    let h = try PolicyReloadHarness(loader: loader)
    defer { h.cleanUp() }
    await h.model.refresh()
    #expect(await h.model.reloadNotificationPolicy() == .loaded(updated))
    #expect(h.model.recovery.policy == updated)
    #expect(await loader.count == 2)
  }

  @Test func schedulingErrorDoesNotInvalidateLoadedPolicy() async throws {
    let policy = try NotificationPolicy(revision: 1)
    let loader = PolicyReloadScript([.loaded(reminders: [], notices: [], policy: policy)])
    let h = try PolicyReloadHarness(loader: loader, client: PolicyReloadFailingNotifications())
    defer { h.cleanUp() }
    #expect(await h.model.reloadNotificationPolicy() == .loaded(policy))
    #expect(h.model.result?.error != nil)
    #expect(await loader.count == 1)
  }

  @Test func olderReloadReportsSupersededRatherThanNewerCachedPolicy() async throws {
    let old = try NotificationPolicy(revision: 1)
    let updated = try NotificationPolicy(bypassQuietHours: true, revision: 2)
    let loader = PolicyReloadGate()
    let h = try PolicyReloadHarness(loader: loader)
    defer { h.cleanUp() }
    let earlier = Task { await h.model.reloadNotificationPolicy() }
    await loader.waitForCount(1)
    let later = Task { await h.model.refresh() }
    await loader.waitForCount(2)
    await loader.finish(2, policy: updated)
    await later.value
    await loader.finish(1, policy: old)
    #expect(await earlier.value == .superseded)
    #expect(h.model.recovery.policy == updated)
  }

  @Test func explicitPolicySaveDuringReconciliationSupersedesReloadOutcome() async throws {
    let policy = try NotificationPolicy(revision: 1)
    let loader = PolicyReloadScript([.loaded(reminders: [], notices: [], policy: policy)])
    let client = PolicyReloadPausedNotifications()
    let h = try PolicyReloadHarness(loader: loader, client: client)
    defer { h.cleanUp() }
    let reload = Task { await h.model.reloadNotificationPolicy() }
    await client.waitUntilEntered()
    #expect(h.model.recovery.savePolicy(try NotificationPolicy(bypassQuietHours: true), expectedRevision: 1))
    await client.release()
    #expect(await reload.value == .superseded)
    #expect(h.model.recovery.policy?.revision == 2)
    #expect(h.model.recovery.policy?.bypassQuietHours == true)
  }
}

@MainActor private final class PolicyReloadHarness {
  let directory: URL
  let model: AppModel
  init(loader: any ReminderRefreshLoading, client: any NotificationClient = FakeNotifications()) throws {
    directory = FileManager.default.temporaryDirectory.appendingPathComponent("PolicyReloadTests.\(UUID())")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let store = try ReminderStore(databaseURL: directory.appendingPathComponent("fixture.sqlite"))
    model = AppModel(store: store, client: client,
      clock: { Date(timeIntervalSince1970: 1_800_000_000) }, refreshLoader: loader)
  }
  func cleanUp() { try? FileManager.default.removeItem(at: directory) }
}

private actor PolicyReloadScript: ReminderRefreshLoading {
  private var results: [ReminderRefreshLoadResult]
  private(set) var count = 0
  init(_ results: [ReminderRefreshLoadResult]) { self.results = results }
  func load(now: Date, sequence: Int) -> ReminderRefreshLoadResult {
    count += 1
    guard !results.isEmpty else { return .listFailure("unexpected duplicate load") }
    return results.removeFirst()
  }
}

private actor PolicyReloadGate: ReminderRefreshLoading {
  private var count = 0
  private var pending: [Int: CheckedContinuation<ReminderRefreshLoadResult, Never>] = [:]
  func load(now: Date, sequence: Int) async -> ReminderRefreshLoadResult {
    count += 1
    let id = count
    return await withCheckedContinuation { pending[id] = $0 }
  }
  func waitForCount(_ target: Int) async { while count < target { await Task.yield() } }
  func finish(_ id: Int, policy: NotificationPolicy) {
    pending.removeValue(forKey: id)?.resume(returning: .loaded(reminders: [], notices: [], policy: policy))
  }
}

private actor PolicyReloadFailingNotifications: NotificationClient {
  func authorizationStatus() async -> NotificationAuthorization { .authorized }
  func pending() async throws -> [NotificationIntent] { throw PolicyReloadFixtureError.expected }
  func add(_ intent: NotificationIntent) async throws {}
  func remove(ids: [String]) async {}
}

private actor PolicyReloadPausedNotifications: NotificationClient {
  private var entered = false
  private var released = false
  private var continuation: CheckedContinuation<Void, Never>?
  func waitUntilEntered() async { while !entered { await Task.yield() } }
  func release() { released = true; continuation?.resume(); continuation = nil }
  func authorizationStatus() async -> NotificationAuthorization {
    if released { return .denied }
    await withCheckedContinuation { continuation = $0; entered = true }
    return .denied
  }
  func pending() async throws -> [NotificationIntent] { [] }
  func add(_ intent: NotificationIntent) async throws {}
  func remove(ids: [String]) async {}
}
private enum PolicyReloadFixtureError: Error { case expected }
