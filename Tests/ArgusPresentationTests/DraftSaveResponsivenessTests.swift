import Foundation
import Testing
import CSQLite
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

extension AppModelTests {
  @Test func draftSaveLetsMainActorReleaseWriterBeforeSQLiteTimeout() async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let neighbor = try Reminder(title: "Unchanged neighbor", dueAt: now.addingTimeInterval(600),
      timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(neighbor, expectedRevision: nil)
    var draft = ReminderDraft(now: now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "New draft"
    var database: OpaquePointer?
    #expect(sqlite3_open(dir.appendingPathComponent("test.sqlite").path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    #expect(sqlite3_exec(database, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
    let heartbeat = Task { @MainActor in
      #expect(sqlite3_exec(database, "ROLLBACK", nil, nil, nil) == SQLITE_OK)
    }
    let saved = await model.save(draft)
    await heartbeat.value
    #expect(saved)
    #expect(try model.store.reminder(id: neighbor.id) == neighbor)
    #expect(try model.store.list().count == 2)
    #expect(try model.store.generation() == 2)
    #expect(model.message == nil)
    #expect(model.result != nil)
    #expect(!model.isWorking)
  }
}
