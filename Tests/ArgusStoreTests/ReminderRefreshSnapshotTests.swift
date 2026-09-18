import Foundation
import Testing
import ArgusCore
@testable import ArgusStore

struct ReminderRefreshSnapshotTests {
  @Test func coherentSnapshotCapturesAndReadsWithoutChangingGeneration() throws {
    let (url, item) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try ReminderStore(databaseURL: url)
    try store.save(item, expectedRevision: nil)
    let snapshot = try store.refreshSnapshot(now: item.dueAt)
    #expect(snapshot.reminders == [item])
    #expect(snapshot.notices.count == 1)
    #expect(snapshot.policy == (try store.notificationPolicy()))
    #expect(snapshot.notices == (try store.notices(includeDismissed: true)))
    #expect(try store.generation() == 1)
    #expect(try ReminderStore(databaseURL: url).notices().count == 1)
  }

  @Test func finalReadFailureRollsBackCaptureAndTriggerChanges() throws {
    let (url, item) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try ReminderStore(databaseURL: url)
    try store.save(item, expectedRevision: nil)
    let database = try SQLiteDatabase(url: url)
    try database.execute("CREATE TRIGGER corrupt_policy_after_capture AFTER INSERT ON reminder_notices BEGIN UPDATE notification_policy SET payload = x'00'; END")
    #expect(throws: (any Error).self) { try store.refreshSnapshot(now: item.dueAt) }
    #expect(try store.notices(includeDismissed: true).isEmpty)
    #expect(try store.notificationPolicy().revision == 1)
    #expect(try store.generation() == 1)
  }

  @Test func secondConnectionChangesAreVisibleOnNextSnapshotNotRetroactively() throws {
    let (url, item) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try ReminderStore(databaseURL: url)
    try store.save(item, expectedRevision: nil)
    let before = try store.refreshSnapshot(now: item.dueAt)
    let notice = try #require(before.notices.first)
    let other = try ReminderStore(databaseURL: url)
    try other.dismissNotice(id: notice.id, now: item.dueAt)
    #expect(try other.generation() == 1) // Notice changes are NOT fenced by source generation.
    var second = item
    second.id = UUID()
    try other.save(second, expectedRevision: nil)
    _ = try other.captureDueNotices(now: item.dueAt)
    try other.saveNotificationPolicy(NotificationPolicy(bypassQuietHours: true), expectedRevision: 1)
    #expect(before.notices.count == 1)
    #expect(before.notices.first?.dismissedAt == nil)
    #expect(before.policy.revision == 1)
    let after = try store.refreshSnapshot(now: item.dueAt)
    #expect(after.reminders.count == 2)
    #expect(after.notices.count == 2)
    #expect(after.notices.first { $0.id == notice.id }?.dismissedAt == item.dueAt)
    #expect(after.policy.revision == 2)
  }
}
