import Foundation
import Testing
import CSQLite
import ArgusCore
import ArgusPlatform
import ArgusStore
@testable import ArgusPresentation

private actor PausedAuthorization: NotificationClient {
  private var entered = false
  private var continuation: CheckedContinuation<Void, Never>?
  func waitUntilEntered() async { while !entered { await Task.yield() } }
  func release() { continuation?.resume(); continuation = nil }
  func authorizationStatus() async -> NotificationAuthorization {
    if !entered {
      await withCheckedContinuation { continuation in self.continuation = continuation; entered = true }
    }
    return .denied
  }
  func pending() async throws -> [NotificationIntent] { [] }
  func add(_ intent: NotificationIntent) async throws {}
  func remove(ids: [String]) async {}
}

@MainActor struct RefreshFailureTests {
  @Test func latestFailedReadTerminatesOverlappingRefresh() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("test.sqlite")
    let store = try ReminderStore(databaseURL: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try store.save(Reminder(title: "Fixture", dueAt: now.addingTimeInterval(600), timeZoneID: "UTC", createdAt: now, updatedAt: now), expectedRevision: nil)
    let client = PausedAuthorization()
    let model = AppModel(store: store, client: client, clock: { now })
    let first = Task { await model.refresh() }
    await client.waitUntilEntered()
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, "UPDATE reminders SET payload = x'00'", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(database)
    await model.refresh()
    await client.release()
    await first.value
    #expect(!model.isReconciling)
    #expect(model.result == nil)
    #expect(model.message?.contains("Could not read") == true)
    #expect(!model.status.contains("checking"))
    #expect(!model.status.contains("Saved locally"))
  }
}
