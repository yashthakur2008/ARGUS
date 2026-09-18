import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPlatform

// Baseline red used a test-only token-ignoring adapter to the existing API.
struct ReconciliationRequestOrderTests {
  @Test(arguments: [false, true])
  func obsoleteAfterCompletionCannotChangeNewestPendingWindow(clockReversed: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    let source = try Reminder(title: "Crossed deadline", dueAt: start.addingTimeInterval(60),
      timeZoneID: "UTC", createdAt: start, updatedAt: start)
    try store.save(source, expectedRevision: nil)
    let client = OrderedNotifications()
    let reconciler = NotificationReconciler(store: store, client: client)
    let newestNow = clockReversed ? start : start.addingTimeInterval(120)
    let olderNow = clockReversed ? start.addingTimeInterval(120) : start
    let newest = await reconciler.reconcileSystemNotifications(now: newestNow, requestSequence: 3)
    let expected = try store.desiredSystemNotifications(now: newestNow)
    #expect(try await client.pending() == expected)
    let calls = await client.calls
    let obsolete = await reconciler.reconcileSystemNotifications(now: olderNow, requestSequence: 2)
    #expect(obsolete == newest)
    #expect(try await client.pending() == expected)
    // pending() is also counted; one assertion read happened after the snapshot.
    #expect(await client.calls == calls + 1)
    #expect(try store.list() == [source])
  }

  // Deterministic production admission + actual gated reconciliation pass.
  // This is not a timing-based reproduction of public actor job scheduling.
  @Test(arguments: [false, true])
  func reorderedAdmissionKeepsNewestLogicalWindow(clockReversed: Bool) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.url) }
    await f.client.configure(pause: true)
    let initial = Task { await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: 1) }
    await f.client.waitUntilPaused()
    let newestNow = clockReversed ? f.now : f.now.addingTimeInterval(120)
    let obsoleteNow = clockReversed ? f.now.addingTimeInterval(120) : f.now
    #expect(await f.reconciler.admitWindow(now: newestNow, horizon: nil, requestSequence: 3))
    #expect(!(await f.reconciler.admitWindow(now: obsoleteNow, horizon: nil, requestSequence: 2)))
    await f.client.release()
    let result = await initial.value
    let expected = try f.store.desiredSystemNotifications(now: newestNow)
    #expect(try await f.client.pending() == expected)
    #expect(result.scheduledCount == expected.count)
    #expect(!result.isPending)
    let calls = await f.client.calls
    let newestCaller = await f.reconciler.reconcileSystemNotifications(now: newestNow, requestSequence: 3)
    #expect(newestCaller == result)
    #expect(await f.client.calls == calls)
  }

  @Test(arguments: ["success", "denied", "error"])
  func obsoleteAndDuplicateRequestsReuseEveryCompletion(mode: String) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.url) }
    await f.client.configure(status: mode == "denied" ? .denied : .authorized, failPending: mode == "error")
    let latest = await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: -4)
    #expect(latest.isPending == (mode != "success"))
    #expect((latest.error != nil) == (mode != "success"))
    let calls = await f.client.calls
    #expect(await f.reconciler.reconcileSystemNotifications(now: f.now.addingTimeInterval(120), requestSequence: -5) == latest)
    #expect(await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: -4) == latest)
    #expect(await f.client.calls == calls)
    await f.client.configure()
    _ = await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: -3)
    #expect(await f.client.calls > calls)
  }

  @Test func mixedUnsequencedOverrideRetainsLegacyArrivalSemantics() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.url) }
    _ = await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: 3)
    let late = f.now.addingTimeInterval(120)
    let legacy = await f.reconciler.reconcileSystemNotifications(now: late)
    #expect(try await f.client.pending().isEmpty)
    let calls = await f.client.calls
    #expect(await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: 2) == legacy)
    #expect(await f.client.calls == calls)
    // A fresh logical request can restore its window; wall clock need not increase.
    _ = await f.reconciler.reconcileSystemNotifications(now: f.now, requestSequence: 4)
    #expect(try await f.client.pending().count == 1)
    _ = await f.reconciler.reconcile(now: late, horizon: late.addingTimeInterval(600))
    #expect(try await f.client.pending().isEmpty)
  }

  private func fixture() throws -> (store: ReminderStore, client: OrderedNotifications,
    reconciler: NotificationReconciler, now: Date, url: URL) {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let store = try ReminderStore(databaseURL: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try store.save(Reminder(title: "Crossing", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now), expectedRevision: nil)
    let client = OrderedNotifications()
    return (store, client, NotificationReconciler(store: store, client: client), now, url)
  }

}

private actor OrderedNotifications: NotificationClient {
  private var values: [String: NotificationIntent] = [:]
  private(set) var calls = 0
  private var status: NotificationAuthorization = .authorized
  private var failPending = false
  private var pauseAuthorization = false
  private var gate: CheckedContinuation<Void, Never>?
  private var observer: CheckedContinuation<Void, Never>?
  enum Failure: Error { case pending }
  func configure(status: NotificationAuthorization = .authorized, failPending: Bool = false, pause: Bool = false) {
    self.status = status; self.failPending = failPending; pauseAuthorization = pause
  }
  func authorizationStatus() async -> NotificationAuthorization {
    calls += 1
    if pauseAuthorization {
      pauseAuthorization = false
      await withCheckedContinuation { gate = $0; observer?.resume(); observer = nil }
    }
    return status
  }
  func waitUntilPaused() async {
    if gate != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func release() { gate?.resume(); gate = nil }
  func pending() throws -> [NotificationIntent] {
    calls += 1
    if failPending { throw Failure.pending }
    return values.values.sorted { $0.id < $1.id }
  }
  func add(_ intent: NotificationIntent) { calls += 1; values[intent.id] = intent }
  func remove(ids: [String]) { calls += 1; for id in ids { values.removeValue(forKey: id) } }
}
