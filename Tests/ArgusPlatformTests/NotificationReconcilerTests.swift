import Foundation
import Testing
import ArgusCore
import ArgusStore
import ArgusPlatform

actor FakeNotifications: NotificationClient {
  var status: NotificationAuthorization = .authorized
  var values: [String: NotificationIntent] = [:]
  var adds = 0
  var activeAdds = 0
  var maximumActiveAdds = 0
  var failAdd = false
  var failPending = false
  var pauseNextAdd = false
  var addGate: CheckedContinuation<Void, Never>?
  var pauseObserver: CheckedContinuation<Void, Never>?
  enum Failure: Error { case failed }
  func authorizationStatus() -> NotificationAuthorization { status }
  func pending() throws -> [NotificationIntent] {
    if failPending { throw Failure.failed }
    return Array(values.values)
  }
  func add(_ intent: NotificationIntent) async throws {
    activeAdds += 1
    maximumActiveAdds = max(maximumActiveAdds, activeAdds)
    defer { activeAdds -= 1 }
    await Task.yield()
    if pauseNextAdd {
      pauseNextAdd = false
      await withCheckedContinuation { continuation in
        addGate = continuation
        pauseObserver?.resume()
        pauseObserver = nil
      }
    }
    if failAdd { throw Failure.failed }
    adds += 1
    values[intent.id] = intent
  }
  func remove(ids: [String]) { for id in ids { values.removeValue(forKey: id) } }
  func setStatus(_ value: NotificationAuthorization) { status = value }
  func setFailure(_ value: Bool) { failAdd = value }
  func setPendingFailure(_ value: Bool) { failPending = value }
  func pauseAdd() { pauseNextAdd = true }
  func waitForPausedAdd() async {
    if addGate != nil { return }
    await withCheckedContinuation { pauseObserver = $0 }
  }
  func releaseAdd() { addGate?.resume(); addGate = nil }
}

@Test func reconcilesIdempotentlyAndPreservesOtherApps() async throws {
  let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  defer { try? FileManager.default.removeItem(at: url) }
  let store = try ReminderStore(databaseURL: url)
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "Tea", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  let other = NotificationIntent(id: "other.app", reminderID: UUID(), title: "Other", fireAt: now, sourceRevision: 1)
  try await client.add(other)
  let reconciler = NotificationReconciler(store: store, client: client)
  let result = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600))
  #expect(!result.isPending)
  #expect(result.scheduledCount == 1)
  _ = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600))
  #expect(await client.adds == 2)
  try store.delete(id: reminder.id, expectedRevision: 1)
  _ = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600))
  #expect(try await client.pending() == [other])
}

@Test func failureRestartAndRevocationKeepDatabaseTruth() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("state.sqlite")
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let horizon = now.addingTimeInterval(3600)
  let reminder = try Reminder(title: "Tea", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  await client.setFailure(true)
  let failed = await NotificationReconciler(store: store, client: client).reconcile(now: now, horizon: horizon)
  #expect(failed.isPending)
  #expect(failed.error != nil)
  #expect(try store.list() == [reminder])
  await client.setFailure(false)
  let reopened = try ReminderStore(databaseURL: url)
  let retry = await NotificationReconciler(store: reopened, client: client).reconcile(now: now, horizon: horizon)
  #expect(!retry.isPending)
  #expect(retry.generation == 1)
  await client.setStatus(.denied)
  let denied = await NotificationReconciler(store: reopened, client: client).reconcile(now: now, horizon: horizon)
  #expect(denied.isPending)
  #expect(denied.authorization == .denied)
  #expect(try reopened.list() == [reminder])
  #expect(try await client.pending().isEmpty)
}

@Test func editDuringDelayedAddRerunsWithoutASecondRequest() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  var reminder = try Reminder(title: "Old", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  await client.pauseAdd()
  let reconciler = NotificationReconciler(store: store, client: client)
  let task = Task { await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600)) }
  await client.waitForPausedAdd()
  reminder.title = "New"
  reminder.dueAt = now.addingTimeInterval(120)
  try store.save(reminder, expectedRevision: 1)
  await client.releaseAdd()
  let result = await task.value
  #expect(!result.isPending)
  #expect(result.generation == 2)
  let pending = try await client.pending()
  #expect(pending.count == 1)
  #expect(pending.first?.title == "New")
  #expect(pending.first?.sourceRevision == 2)
  #expect(pending.first?.fireAt == reminder.dueAt)
}

@Test func revokedDuringDelayedAddRemovesStaleOwnedRequest() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "Private", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  let other = NotificationIntent(id: "another.app", reminderID: UUID(), title: "Untouched", fireAt: now, sourceRevision: 1)
  try await client.add(other)
  await client.pauseAdd()
  let reconciler = NotificationReconciler(store: store, client: client)
  let task = Task { await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600)) }
  await client.waitForPausedAdd()
  await client.setStatus(.denied)
  await client.releaseAdd()
  let result = await task.value
  #expect(result.isPending)
  #expect(result.authorization == .denied)
  #expect(try await client.pending() == [other])
  #expect(try store.list() == [reminder])
}

@Test func pendingFailureIsVisibleAndRetryConverges() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let client = FakeNotifications()
  let reconciler = NotificationReconciler(store: store, client: client)
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  await client.setPendingFailure(true)
  let failed = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(60))
  #expect(failed.isPending)
  #expect(failed.error != nil)
  await client.setPendingFailure(false)
  let recovered = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(60))
  #expect(!recovered.isPending)
  #expect(recovered.generation == 0)
}

@Test func concurrentReconciliationCallsShareOneFlight() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "One", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  let reconciler = NotificationReconciler(store: store, client: client)
  let results = await withTaskGroup(of: ReconciliationResult.self) { group in
    for _ in 0..<32 {
      group.addTask { await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600)) }
    }
    var results: [ReconciliationResult] = []
    for await result in group { results.append(result) }
    return results
  }
  #expect(results.count == 32)
  #expect(results.allSatisfy { !$0.isPending && $0.generation == 1 && $0.scheduledCount == 1 })
  #expect(await client.adds == 1)
  #expect(await client.maximumActiveAdds == 1)
  #expect(try await client.pending() == store.desiredNotifications(now: now, horizon: now.addingTimeInterval(3600)))
}

@Test(arguments: [NotificationAuthorization.notDetermined, .denied, .provisional, .authorized])
func authorizationStatesAreReportedHonestly(status: NotificationAuthorization) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "One", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  await client.setStatus(status)
  let result = await NotificationReconciler(store: store, client: client).reconcile(now: now, horizon: now.addingTimeInterval(3600))
  let allowed = status == .authorized || status == .provisional
  #expect(result.authorization == status)
  #expect(result.isPending == !allowed)
  #expect(result.scheduledCount == (allowed ? 1 : 0))
  #expect(try store.list() == [reminder])
}

@Test func deleteDuringDelayedAddRemovesJustDeletedIntent() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "Deleted", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  await client.pauseAdd()
  let reconciler = NotificationReconciler(store: store, client: client)
  let task = Task { await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600)) }
  await client.waitForPausedAdd()
  try store.delete(id: reminder.id, expectedRevision: 1)
  await client.releaseAdd()
  let result = await task.value
  #expect(!result.isPending)
  #expect(result.generation == 2)
  #expect(result.scheduledCount == 0)
  #expect(try await client.pending().isEmpty)
}

@Test func sameIdentifierEditReplacesContentAndRevision() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  var reminder = try Reminder(title: "Before", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  let reconciler = NotificationReconciler(store: store, client: client)
  _ = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600))
  let firstID = try await client.pending().first?.id
  reminder.title = "After"
  try store.save(reminder, expectedRevision: 1)
  let result = await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600))
  let pending = try await client.pending()
  #expect(!result.isPending)
  #expect(pending.count == 1)
  #expect(pending.first?.id == firstID)
  #expect(pending.first?.title == "After")
  #expect(pending.first?.sourceRevision == 2)
}

@Test(arguments: [false, true])
func knownStaleAddIsRemovedEvenWhenNextPendingFails(revoke: Bool) async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "Stale", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  let other = NotificationIntent(id: "another.app", reminderID: UUID(), title: "Untouched", fireAt: now, sourceRevision: 1)
  try await client.add(other)
  await client.pauseAdd()
  let reconciler = NotificationReconciler(store: store, client: client)
  let task = Task { await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(3600)) }
  await client.waitForPausedAdd()
  if revoke { await client.setStatus(.denied) }
  else { try store.delete(id: reminder.id, expectedRevision: 1) }
  await client.setPendingFailure(true)
  await client.releaseAdd()
  let result = await task.value
  #expect(result.isPending)
  #expect(result.error != nil)
  #expect(await client.values.count == 1)
  #expect(await client.values[other.id] == other)
}

@Test func recoverySystemReconcilesMonthAwayAfterRestartWithoutCatchUpBurst() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("state.sqlite")
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let store = try ReminderStore(databaseURL: url)
  let future = try Reminder(title: "Month away", dueAt: now.addingTimeInterval(30 * 86400), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  let past = try Reminder(title: "Past", dueAt: now.addingTimeInterval(-30 * 86400), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(future, expectedRevision: nil)
  try store.save(past, expectedRevision: nil)
  #expect(try store.captureDueNotices(now: now).activeCount == 1)
  let client = FakeNotifications()
  let result = await NotificationReconciler(store: store, client: client).reconcileSystemNotifications(now: now)
  #expect(!result.isPending)
  #expect(result.scheduledCount == 1)
  #expect(try await client.pending().first?.reminderID == future.id)
  let reopened = try ReminderStore(databaseURL: url)
  let retry = await NotificationReconciler(store: reopened, client: client).reconcileSystemNotifications(now: now)
  #expect(!retry.isPending)
  #expect(await client.adds == 1)
  await client.setStatus(.denied)
  let denied = await NotificationReconciler(store: reopened, client: client).reconcileSystemNotifications(now: now)
  #expect(denied.isPending)
  #expect(denied.authorization == .denied)
  #expect(try reopened.captureDueNotices(now: now).activeCount == 1)
  #expect(try reopened.list().count == 2)
}

@Test func recoveryMixedPlanningEntryPointsShareOneFlight() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let reminder = try Reminder(title: "Month", dueAt: now.addingTimeInterval(30 * 86400), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  let reconciler = NotificationReconciler(store: store, client: client)
  let results = await withTaskGroup(of: ReconciliationResult.self) { group in
    for index in 0..<32 {
      group.addTask {
        if index.isMultiple(of: 2) { return await reconciler.reconcileSystemNotifications(now: now) }
        return await reconciler.reconcile(now: now, horizon: now.addingTimeInterval(40 * 86400))
      }
    }
    var values: [ReconciliationResult] = []
    for await value in group { values.append(value) }
    return values
  }
  #expect(results.count == 32)
  #expect(results.allSatisfy { !$0.isPending && $0.scheduledCount == 1 })
  #expect(await client.maximumActiveAdds == 1)
  #expect(await client.adds == 1)
}

@Test func recoveryPolicyEditDuringAddRemovesOldRequestAndUsesDeferredPlan() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let store = try ReminderStore(databaseURL: directory.appendingPathComponent("state.sqlite"))
  let now = Date(timeIntervalSince1970: 1_800_000_000) // 08:00 UTC
  let reminder = try Reminder(title: "Quiet", dueAt: now.addingTimeInterval(60), timeZoneID: "UTC", createdAt: now, updatedAt: now)
  try store.save(reminder, expectedRevision: nil)
  let client = FakeNotifications()
  await client.pauseAdd()
  let reconciler = NotificationReconciler(store: store, client: client)
  let task = Task { await reconciler.reconcileSystemNotifications(now: now) }
  await client.waitForPausedAdd()
  let quiet = try QuietHours(startHour: 8, startMinute: 0, endHour: 9, endMinute: 0, timeZoneID: "UTC")
  try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  await client.releaseAdd()
  let result = await task.value
  #expect(!result.isPending)
  #expect(result.generation == 2)
  let pending = try await client.pending()
  #expect(pending.count == 1)
  #expect(pending.first?.fireAt == quiet.nextAllowedDate(for: reminder.dueAt))
  #expect(try store.list().first?.dueAt == reminder.dueAt)
}

@Test func systemReconciliationRetainsFoldDeferredAdvanceAlertAfterRestartAndDeadline() async throws {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  defer { try? FileManager.default.removeItem(at: directory) }
  let url = directory.appendingPathComponent("state.sqlite")
  let formatter = ISO8601DateFormatter()
  let now = formatter.date(from: "2026-11-01T08:00:00Z")!
  let due = formatter.date(from: "2026-11-01T09:15:00Z")!
  let deferred = formatter.date(from: "2026-11-01T10:00:00Z")!
  let reminder = try Reminder(title: "Fold", dueAt: due, timeZoneID: "America/Los_Angeles",
    createdAt: now, updatedAt: now, alertOffsets: [0, 1500])
  let quiet = try QuietHours(startHour: 1, startMinute: 45, endHour: 2, endMinute: 0,
    timeZoneID: "America/Los_Angeles")
  do {
    let store = try ReminderStore(databaseURL: url)
    try store.save(reminder, expectedRevision: nil)
    try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet), expectedRevision: 1)
  }
  let reopened = try ReminderStore(databaseURL: url)
  let client = FakeNotifications()
  let reconciler = NotificationReconciler(store: reopened, client: client)
  let bounded = await reconciler.reconcile(now: now, horizon: deferred)
  #expect(!bounded.isPending)
  #expect(bounded.scheduledCount == 2)
  let system = await reconciler.reconcileSystemNotifications(now: now)
  #expect(!system.isPending)
  #expect(system.scheduledCount == 2)
  #expect(try await client.pending().map(\.fireAt).sorted() == [due, deferred])
  // System mode must retain the delayed advance alert even once dueAt has passed.
  let afterDeadline = await reconciler.reconcileSystemNotifications(now: formatter.date(from: "2026-11-01T09:30:00Z")!)
  #expect(!afterDeadline.isPending)
  #expect(afterDeadline.scheduledCount == 1)
  #expect(try await client.pending().map(\.fireAt) == [deferred])
}
