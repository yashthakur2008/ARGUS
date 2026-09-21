import Foundation
import Testing
import ArgusCore
import ArgusStore
import ArgusPlatform
@testable import ArgusPresentation

@MainActor struct RefreshPublicationTests {
  @Test(arguments: [false, true], [false, true])
  func olderSuccessOrFailureCannotOverwriteLatest(olderSuccess: Bool, latestSuccess: Bool) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    let baseline = Task { await f.model.refresh() }
    await f.gate.waitForLoads(1)
    await f.gate.complete(0, with: loaded(f.snapshot))
    await baseline.value
    #expect(f.model.result != nil)
    let older = Task { await f.model.refreshOutcome() }
    await f.gate.waitForLoads(2)
    let latest = Task { await f.model.refreshOutcome() }
    await f.gate.waitForLoads(3)
    var newest = f.item
    newest.title = "Newest"
    let newestResult: ReminderRefreshLoadResult = latestSuccess
      ? .loaded(reminders: [newest], notices: [], policy: f.snapshot.policy)
      : .recoveryFailure(reminders: [newest], message: "latest failure")
    await f.gate.complete(2, with: newestResult)
    #expect(await latest.value == (latestSuccess ? .loaded(f.snapshot.policy) : .failed))
    let notices = f.model.recovery.notices
    let policy = f.model.recovery.policy
    let result = f.model.result
    let message = f.model.message
    #expect((result != nil) == latestSuccess)
    #expect((f.model.noticesUnavailableMessage == nil) == latestSuccess)
    if !latestSuccess { #expect(notices == f.snapshot.notices) }
    await f.gate.complete(1, with: olderSuccess ? loaded(f.snapshot) : .listFailure("older failure"))
    #expect(await older.value == .superseded)
    #expect(f.model.reminders == [newest])
    #expect(f.model.recovery.notices == notices)
    #expect(f.model.recovery.policy == policy)
    #expect(f.model.result == result)
    #expect(f.model.message == message)
    #expect(!f.model.isReconciling)
  }

  @Test(arguments: ["dismiss", "snooze", "policy", "refresh"], [false, true])
  func directRecoveryChangesFencePendingPublication(action: String, oldFailure: Bool) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    try f.model.recovery.refresh(now: f.now)
    let older = Task { await f.model.refreshOutcome() }
    await f.gate.waitForLoads(1)
    let notice = try #require(f.snapshot.notices.first)
    switch action {
    case "dismiss": #expect(f.model.recovery.dismiss(notice, now: f.now))
    case "snooze":
      #expect(f.model.recovery.snooze(notice, occurrenceAt: f.item.dueAt,
        until: f.now.addingTimeInterval(600), expectedRevision: 1, now: f.now))
    case "policy":
      #expect(f.model.recovery.savePolicy(try NotificationPolicy(bypassQuietHours: true), expectedRevision: 1))
    default:
      var another = f.item
      another.id = UUID()
      try f.store.save(another, expectedRevision: nil)
      try f.model.recovery.refresh(now: f.now)
    }
    let notices = f.model.recovery.notices
    let policy = f.model.recovery.policy
    await f.gate.complete(0, with: oldFailure ? .listFailure("stale error") : loaded(f.snapshot))
    #expect(await older.value == .superseded)
    #expect(f.model.recovery.notices == notices)
    #expect(f.model.recovery.policy == policy)
    #expect(f.model.message == nil)
    #expect(f.model.noticesUnavailableMessage == nil)
    #expect(f.model.result == nil)
    #expect(!f.model.isReconciling)
  }

  @Test(arguments: [false, true])
  func modelEditOrDeleteFencesOlderLoad(delete: Bool) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    let older = Task { await f.model.refresh() }
    await f.gate.waitForLoads(1)
    var draft = ReminderDraft(original: f.item, now: f.now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "Updated locally"
    if delete { f.model.requestDeletion(f.item) }
    let changed = Task { @MainActor in
      if delete { await f.model.confirmDeletion(); return true }
      return await f.model.save(draft)
    }
    await f.gate.waitForLoads(2)
    let current = try f.store.refreshSnapshot(now: f.now)
    await f.gate.complete(1, with: loaded(current))
    #expect(await changed.value)
    await f.gate.complete(0, with: loaded(f.snapshot))
    await older.value
    #expect(f.model.reminders == current.reminders)
    #expect(f.model.recovery.notices == current.notices)
    #expect(f.model.result != nil)
    #expect(!f.model.isReconciling)
  }

  @Test(arguments: ["dismiss", "policy"])
  func publicRecoveryMutationRefreshWinsOverOlderLoad(action: String) async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    try f.model.recovery.refresh(now: f.now)
    let older = Task { await f.model.refreshOutcome() }
    await f.gate.waitForLoads(1)
    let mutation = Task { @MainActor in
      switch action {
      case "dismiss":
        await f.model.dismissNotice(try #require(f.model.recovery.activeNotices.first))
        return true
      default:
        let policy = try NotificationPolicy(bypassQuietHours: true)
        return await f.model.saveNotificationPolicy(policy, expectedRevision: f.snapshot.policy.revision)
      }
    }
    await f.gate.waitForLoads(2)
    let current = try f.store.refreshSnapshot(now: f.now)
    await f.gate.complete(1, with: loaded(current))
    #expect(try await mutation.value)
    await f.gate.complete(0, with: loaded(f.snapshot))
    await older.value
    #expect(f.model.reminders == current.reminders)
    #expect(f.model.recovery.notices == current.notices)
    #expect(f.model.recovery.policy == current.policy)
    #expect(f.model.result != nil)
    #expect(f.model.message == nil)
    #expect(!f.model.isReconciling)
  }

  @Test func capturedClockIsUsedForLoadAndReconciliation() async throws {
    let f = try fixture()
    defer { try? FileManager.default.removeItem(at: f.dir) }
    var future = f.item
    future.dueAt = f.now.addingTimeInterval(600)
    try f.store.save(future, expectedRevision: 1)
    let client = SnapshotNotifications()
    let clock = FixtureClock(f.now)
    let model = AppModel(store: f.store, client: client, clock: { clock.read() }, refreshLoader: f.gate)
    let pending = Task { await model.refresh() }
    await f.gate.waitForLoads(1)
    clock.advance(7200)
    await f.gate.complete(0, with: loaded(try f.store.refreshSnapshot(now: f.now)))
    await pending.value
    #expect(await f.gate.dates == [f.now])
    #expect(model.referenceDate == f.now)
    #expect(model.result?.scheduledCount == 1)
    #expect(await client.pending().map(\.fireAt) == [future.dueAt])
  }

  @Test func hundredRequestsShareOneLatestFollowup() async throws {
    let gate = GatedRefreshLoader()
    let loader = ReminderRefreshLoader(worker: gate)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let first = await loader.enqueue(now: now, sequence: 0)
    await gate.waitForLoads(1)
    var pending: [Task<ReminderRefreshLoadResult, Never>] = []
    for index in 1..<100 {
      pending.append(await loader.enqueue(now: now.addingTimeInterval(Double(index)), sequence: index))
    }
    #expect(await gate.dates == [now])
    await gate.complete(0, with: .listFailure("first group"))
    await gate.waitForLoads(2)
    #expect(await gate.dates == [now, now.addingTimeInterval(99)])
    await gate.finishAll(with: .listFailure("latest group"))
    guard case .listFailure("first group") = await first.value else { Issue.record("Wrong first result"); return }
    for task in pending {
      guard case .listFailure("latest group") = await task.value else { Issue.record("Wrong joined result"); continue }
    }
    #expect(await gate.dates.count == 2)
  }

  @Test func reorderedRequestsUseNewestSequenceEvenWhenClockReverses() async {
    let gate = GatedRefreshLoader()
    let loader = ReminderRefreshLoader(worker: gate)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let first = await loader.enqueue(now: now, sequence: 1)
    await gate.waitForLoads(1)
    let newest = await loader.enqueue(now: now.addingTimeInterval(-3600), sequence: 3)
    let lateOlder = await loader.enqueue(now: now.addingTimeInterval(3600), sequence: 2)
    await gate.complete(0, with: .listFailure("first"))
    await gate.waitForLoads(2)
    #expect(await gate.dates == [now, now.addingTimeInterval(-3600)])
    await gate.finishAll(with: .listFailure("newest"))
    _ = await first.value
    _ = await newest.value
    _ = await lateOlder.value
    #expect(await gate.dates.count == 2)
  }

  @Test func staleArrivalAfterCompletedLoadDoesNotScheduleMoreIO() async {
    let gate = GatedRefreshLoader()
    let loader = ReminderRefreshLoader(worker: gate)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let newest = await loader.enqueue(now: now, sequence: 3)
    await gate.waitForLoads(1)
    await gate.finishAll(with: .listFailure("newest"))
    _ = await newest.value
    let older = await loader.enqueue(now: now.addingTimeInterval(3600), sequence: 2)
    _ = await older.value
    #expect(await gate.dates == [now])
  }

  private func loaded(_ s: ReminderRefreshSnapshot) -> ReminderRefreshLoadResult {
    .loaded(reminders: s.reminders, notices: s.notices, policy: s.policy)
  }
  private func fixture() throws -> (model: AppModel, store: ReminderStore, item: Reminder,
    snapshot: ReminderRefreshSnapshot, gate: GatedRefreshLoader, dir: URL, now: Date) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let item = try Reminder(title: "Snapshot fixture", dueAt: now.addingTimeInterval(-60),
      timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try store.save(item, expectedRevision: nil)
    let snapshot = try store.refreshSnapshot(now: now)
    let gate = GatedRefreshLoader()
    return (AppModel(store: store, client: FakeNotifications(), clock: { now }, refreshLoader: gate),
      store, item, snapshot, gate, dir, now)
  }
}

private actor GatedRefreshLoader: ReminderRefreshLoading {
  private(set) var dates: [Date] = []
  private var pending: [Int: CheckedContinuation<ReminderRefreshLoadResult, Never>] = [:]
  private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
  private var automatic: ReminderRefreshLoadResult?
  func load(now: Date, sequence: Int) async -> ReminderRefreshLoadResult {
    let id = dates.count
    dates.append(now)
    let ready = observers.filter { dates.count >= $0.0 }
    observers.removeAll { dates.count >= $0.0 }
    for observer in ready { observer.1.resume() }
    if let automatic { return automatic }
    return await withCheckedContinuation { pending[id] = $0 }
  }
  func waitForLoads(_ count: Int) async {
    if dates.count >= count { return }
    await withCheckedContinuation { observers.append((count, $0)) }
  }
  func complete(_ id: Int, with result: ReminderRefreshLoadResult) { pending.removeValue(forKey: id)?.resume(returning: result) }
  func finishAll(with result: ReminderRefreshLoadResult) {
    automatic = result
    let continuations = pending.values
    pending.removeAll()
    for continuation in continuations { continuation.resume(returning: result) }
  }
}

private actor SnapshotNotifications: NotificationClient {
  private var intents: [NotificationIntent] = []
  func authorizationStatus() async -> NotificationAuthorization { .authorized }
  func pending() async -> [NotificationIntent] { intents }
  func add(_ intent: NotificationIntent) async throws { intents.removeAll { $0.id == intent.id }; intents.append(intent) }
  func remove(ids: [String]) async { intents.removeAll { ids.contains($0.id) } }
}
