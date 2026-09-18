import Foundation
import Testing
import CSQLite
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

@MainActor struct RefreshResponsivenessTests {
  @Test func mainActorCanReleaseWriterWhileRefreshWaits() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("test.sqlite")
    let store = try ReminderStore(databaseURL: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let model = AppModel(store: store, client: FakeNotifications(), clock: { now })
    var database: OpaquePointer?
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    #expect(sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
    // No timing threshold: this queued MainActor task must run before the SQLite
    // busy timeout so refresh can complete successfully, rather than report a lock.
    let heartbeat = Task { @MainActor in
      #expect(sqlite3_exec(database, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
    }
    await model.refresh()
    await heartbeat.value
    #expect(model.message == nil)
    #expect(model.noticesUnavailableMessage == nil)
    #expect(model.result != nil)
    #expect(!model.isReconciling)
  }
}
