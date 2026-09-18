import Foundation
import Testing
import CSQLite
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

@MainActor struct NoticesPresentationTests {
  // Regresses dropping refresh failures from the actual Notices display values,
  // both before any notice exists and while retaining an earlier history snapshot.
  @Test(arguments: [false, true], [false, true])
  func failedRefreshQualifiesNoticesAndSuccessfulRetryRestoresDisplay(cached: Bool, corruptPolicy: Bool) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("notices.sqlite")
    let store = try ReminderStore(databaseURL: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let reminder = try Reminder(title: "Fixture", dueAt: now.addingTimeInterval(cached ? -600 : 600),
      timeZoneID: "UTC", createdAt: now.addingTimeInterval(-1200), updatedAt: now,
      alertOffsets: [0, 60])
    try store.save(reminder, expectedRevision: nil)
    let model = AppModel(store: store, client: FakeNotifications(), clock: { now })
    await model.refresh()
    if cached {
      let notice = try #require(model.recovery.activeNotices.first)
      await model.dismissNotice(notice)
      #expect(model.recovery.notices.count == 2)
      #expect(model.recovery.activeNotices.count == 1)
    }
    let history = model.recovery.notices
    let generation = try store.generation()
    let view = NoticesView(model: model)
    #expect(view.noticeIssue == nil)
    #expect(view.emptyTitle == "No notices here")

    var database: OpaquePointer?
    try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
    defer { sqlite3_close(database) }
    let table = corruptPolicy ? "notification_policy" : "reminders"
    try #require(sqlite3_exec(database, "CREATE TEMP TABLE original_payload AS SELECT id, payload FROM \(table)", nil, nil, nil) == SQLITE_OK)
    try #require(sqlite3_exec(database, "UPDATE \(table) SET payload = x'00'", nil, nil, nil) == SQLITE_OK)
    await model.refresh()

    #expect(model.message?.contains("Could not read") == true)
    #expect(view.noticeIssue?.contains("unavailable") == true)
    #expect(view.emptyTitle == "Notices unavailable")
    #expect(model.recovery.notices == history)
    #expect(try store.notices(includeDismissed: true) == history)
    #expect(try store.generation() == generation)

    // Repair only the isolated fixture to verify that retry clears the warning
    // without resurrecting dismissed notices or losing retained history.
    try #require(sqlite3_exec(database, "UPDATE \(table) SET payload = (SELECT payload FROM original_payload WHERE original_payload.id = \(table).id)", nil, nil, nil) == SQLITE_OK)
    await model.refresh()
    #expect(view.noticeIssue == nil)
    #expect(view.emptyTitle == "No notices here")
    #expect(model.recovery.notices == history)
    let reopened = try ReminderStore(databaseURL: url)
    #expect(try reopened.notices(includeDismissed: true) == history)
    #expect(try reopened.generation() == generation)
  }
}
