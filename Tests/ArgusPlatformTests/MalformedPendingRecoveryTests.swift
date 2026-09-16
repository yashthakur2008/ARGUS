import Foundation
import UserNotifications
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPlatform

private actor RecoveryNotifications: NotificationClient {
  let now: Date
  var requests: [UNNotificationRequest]
  var removals: [[String]] = []
  var adds = 0
  var reads = 0
  var ignoreRemoval = false
  var failRead: Int?
  var pauseRead: Int?
  var pauseRemoval = false
  var status = NotificationAuthorization.authorized
  var pendingError: PendingNotificationError?
  var gate: CheckedContinuation<Void, Never>?
  var observer: CheckedContinuation<Void, Never>?
  enum Failure: Error { case read }

  init(now: Date, requests: [UNNotificationRequest]) { self.now = now; self.requests = requests }
  func authorizationStatus() -> NotificationAuthorization { status }
  func pending() async throws -> [NotificationIntent] {
    reads += 1
    if let pendingError { throw pendingError }
    if reads == failRead { throw Failure.read }
    let snapshot = requests
    if reads == pauseRead { await pause() }
    return try UserNotificationMapping.pendingIntents(from: snapshot)
  }
  func add(_ intent: NotificationIntent) throws {
    adds += 1
    requests.removeAll { $0.identifier == intent.id }
    requests.append(try UserNotificationMapping.request(for: intent, now: now))
  }
  func remove(ids: [String]) async {
    removals.append(ids)
    if !ignoreRemoval { requests.removeAll { ids.contains($0.identifier) } }
    if pauseRemoval { pauseRemoval = false; await pause() }
  }
  func configure(ignoreRemoval: Bool = false, failRead: Int? = nil,
    pauseRead: Int? = nil, pauseRemoval: Bool = false) {
    self.ignoreRemoval = ignoreRemoval; self.failRead = failRead
    self.pauseRead = pauseRead; self.pauseRemoval = pauseRemoval
  }
  func replaceRequests(_ requests: [UNNotificationRequest]) { self.requests = requests }
  func setStatus(_ status: NotificationAuthorization) { self.status = status }
  func setPendingError(_ error: PendingNotificationError) { pendingError = error }
  func identifiers() -> [String] { requests.map(\.identifier).sorted() }
  private func pause() async {
    await withCheckedContinuation { continuation in
      gate = continuation; observer?.resume(); observer = nil
    }
  }
  func waitForPause() async {
    if gate != nil { return }
    await withCheckedContinuation { observer = $0 }
  }
  func release() { gate?.resume(); gate = nil }
}

struct MalformedPendingRecoveryTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private let badID = "argus.reminder.broken"
  private let foreignID = "another.app"

  @Test(arguments: [false, true])
  func recoversMalformedOwnedRequestsAndVerifiesDesiredState(legacy: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    let reminder = try Reminder(title: "Fixture", dueAt: now.addingTimeInterval(60),
      timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try store.save(reminder, expectedRevision: nil)
    let client = RecoveryNotifications(now: now, requests: [request(badID, version: legacy ? nil : "2"), request(foreignID, version: "999")])
    let result = await NotificationReconciler(store: store, client: client).reconcileSystemNotifications(now: now)
    #expect(!result.isPending)
    #expect(result.scheduledCount == 1)
    #expect(await client.removals == [[badID]])
    #expect(await client.reads == 3)
    #expect(await client.identifiers().contains(foreignID))
    #expect(try await client.pending() == store.desiredSystemNotifications(now: now))
  }

  @Test(arguments: [false, true])
  func unsupportedSnapshotNeverMutatesNotifications(reverse: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    var requests = [request(badID), request("argus.reminder.future", version: "999")]
    if reverse { requests.reverse() }
    let expectedIDs = requests.map(\.identifier).sorted()
    let client = RecoveryNotifications(now: now, requests: requests)
    let result = await NotificationReconciler(store: store, client: client).reconcileSystemNotifications(now: now)
    #expect(result.isPending)
    #expect(result.error?.contains("Update ARGUS") == true)
    #expect(await client.removals.isEmpty)
    #expect(await client.adds == 0)
    #expect(await client.identifiers() == expectedIDs)
  }

  @Test(arguments: [false, true])
  func failedCleanupStaysPendingWithoutRepeatedDeletion(readFails: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    let client = RecoveryNotifications(now: now, requests: [request(badID), request(foreignID)])
    await client.configure(ignoreRemoval: !readFails, failRead: readFails ? 2 : nil)
    let result = await NotificationReconciler(store: store, client: client).reconcileSystemNotifications(now: now)
    #expect(result.isPending)
    #expect(result.error != nil)
    #expect(await client.removals == [[badID]])
    #expect(await client.reads == 2)
    #expect(await client.adds == 0)
    #expect(await client.identifiers().contains(foreignID))
  }

  @Test(arguments: [false, true])
  func freshnessChangeDuringEnumerationDiscardsStaleMalformedIDs(revoke: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    let client = RecoveryNotifications(now: now, requests: [request(badID)])
    await client.configure(pauseRead: 1)
    let reconciler = NotificationReconciler(store: store, client: client)
    let task = Task { await reconciler.reconcileSystemNotifications(now: now) }
    await client.waitForPause()
    let reminder = try Reminder(title: "Changed", dueAt: now.addingTimeInterval(60),
      timeZoneID: "UTC", createdAt: now, updatedAt: now)
    if revoke { await client.setStatus(.denied) }
    else { try store.save(reminder, expectedRevision: nil) }
    await client.replaceRequests([request(badID, version: "999")])
    await client.release()
    let result = await task.value
    #expect(result.isPending)
    #expect(result.generation == (revoke ? 0 : 1))
    #expect(result.error?.contains("Update ARGUS") == true)
    #expect(await client.removals.isEmpty)
    #expect(await client.adds == 0)
  }

  @Test(arguments: [false, true])
  func invalidRecoveryIDsNeverReachRemoval(empty: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    let client = RecoveryNotifications(now: now, requests: [request(foreignID)])
    await client.setPendingError(.malformedOwnedRequests(ids: empty ? [] : [badID, foreignID]))
    let result = await NotificationReconciler(store: store, client: client).reconcileSystemNotifications(now: now)
    #expect(result.isPending)
    #expect(result.error?.contains("Invalid malformed-notification recovery IDs") == true)
    #expect(await client.removals.isEmpty)
    #expect(await client.adds == 0)
    #expect(await client.identifiers() == [foreignID])
  }

  @Test(arguments: [false, true])
  func replacementDuringCleanupIsNotDeletedAgainOrReportedSuccessful(unsupported: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    let client = RecoveryNotifications(now: now, requests: [request(badID)])
    await client.configure(pauseRemoval: true)
    let reconciler = NotificationReconciler(store: store, client: client)
    let task = Task { await reconciler.reconcileSystemNotifications(now: now) }
    await client.waitForPause()
    let replacement: UNNotificationRequest
    if unsupported { replacement = request(badID, version: "999") }
    else {
      let intent = NotificationIntent(id: badID, reminderID: UUID(), title: "Replacement",
        fireAt: now.addingTimeInterval(60), sourceRevision: 1)
      replacement = try UserNotificationMapping.request(for: intent, now: now)
    }
    await client.replaceRequests([replacement])
    await client.release()
    let result = await task.value
    #expect(result.isPending)
    #expect(result.error?.contains(unsupported ? "Update ARGUS" : "removal could not be verified") == true)
    #expect(await client.removals == [[badID]])
    #expect(await client.adds == 0)
    #expect(await client.identifiers() == [badID])
  }

  @Test(arguments: [false, true])
  func changeDuringRemovalRerunsBeforeScheduling(revoke: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let store = try ReminderStore(databaseURL: url)
    var reminder = try Reminder(title: "Before", dueAt: now.addingTimeInterval(60),
      timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try store.save(reminder, expectedRevision: nil)
    let client = RecoveryNotifications(now: now, requests: [request(badID)])
    await client.configure(pauseRemoval: true)
    let reconciler = NotificationReconciler(store: store, client: client)
    let task = Task { await reconciler.reconcileSystemNotifications(now: now) }
    await client.waitForPause()
    if revoke { await client.setStatus(.denied) }
    else {
      reminder.title = "After"
      try store.save(reminder, expectedRevision: 1)
    }
    await client.release()
    let result = await task.value
    #expect(result.isPending == revoke)
    if revoke {
      #expect(result.authorization == .denied)
      #expect(await client.adds == 0)
    } else {
      #expect(result.generation == 2)
      #expect(try await client.pending().first?.title == "After")
      #expect(await client.adds == 1)
    }
  }

  private func request(_ id: String, version: String? = "2") -> UNNotificationRequest {
    let content = UNMutableNotificationContent()
    if let version { content.userInfo = ["mappingVersion": version] }
    return UNNotificationRequest(identifier: id, content: content, trigger: nil)
  }
}
