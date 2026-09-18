import Foundation
import Testing
import ArgusCore
import ArgusStore

func fixture() throws -> (URL, Reminder) {
  let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  return (directory.appendingPathComponent("reminders.sqlite"), try Reminder(title: "買茶 '; DROP TABLE reminders; --", dueAt: now.addingTimeInterval(3600), timeZoneID: "UTC", createdAt: now, updatedAt: now))
}

@Test func saveReopenUpdateDelete() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  #expect(try store.list() == [reminder])
  #expect(try store.generation() == 1)
  let reopened = try ReminderStore(databaseURL: url)
  #expect(try reopened.list() == [reminder])
  var edited = reminder
  edited.title = "Edited"
  edited.revision = 99
  edited.createdAt = reminder.createdAt.addingTimeInterval(40)
  try reopened.save(edited, expectedRevision: 1)
  let saved = try #require(reopened.list().first)
  #expect(saved.revision == 2)
  #expect(saved.createdAt == reminder.createdAt)
  #expect(throws: StoreError.conflict) { try store.save(reminder, expectedRevision: 1) }
  #expect(throws: StoreError.conflict) { try store.save(reminder, expectedRevision: nil) }
  #expect(throws: StoreError.conflict) { try store.delete(id: reminder.id, expectedRevision: 1) }
  #expect(try store.generation() == 2)
  try store.delete(id: reminder.id, expectedRevision: 2)
  #expect(try ReminderStore(databaseURL: url).list().isEmpty)
  #expect(try store.generation() == 3)
}

@Test func rejectsInvalidAndNeverResetsBadFile() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  var invalid = reminder
  invalid.timeZoneID = "not/a/zone"
  #expect(throws: (any Error).self) { try store.save(invalid, expectedRevision: nil) }
  #expect(try store.generation() == 0)
  let bad = url.deletingLastPathComponent().appendingPathComponent("broken.sqlite")
  let bytes = Data("not a database".utf8)
  try bytes.write(to: bad)
  #expect(throws: (any Error).self) { _ = try ReminderStore(databaseURL: bad) }
  #expect(try Data(contentsOf: bad) == bytes)
}

@Test func desiredStatePersistsAndRejectsStaleDelete() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  let store = try ReminderStore(databaseURL: url)
  try store.save(reminder, expectedRevision: nil)
  let expected = try ScheduleCalculator.notifications(for: reminder, now: reminder.createdAt, horizon: reminder.dueAt)
  #expect(try store.desiredNotifications(now: reminder.createdAt, horizon: reminder.dueAt) == expected)
  #expect(throws: StoreError.conflict) { try store.delete(id: UUID(), expectedRevision: 1) }
  #expect(try ReminderStore(databaseURL: url).generation() == 1)
}

@Test func closedConnectionReopensAndCreateRevisionIsOwnedByStore() throws {
  let (url, reminder) = try fixture()
  defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
  func writeAndClose() throws {
    let store = try ReminderStore(databaseURL: url)
    var input = reminder
    input.revision = 42
    input.alertOffsets = [60, 0, 60]
    try store.save(input, expectedRevision: nil)
  }
  try writeAndClose()
  let reopened = try ReminderStore(databaseURL: url)
  let saved = try #require(reopened.list().first)
  #expect(saved.revision == 1)
  #expect(saved.alertOffsets == [0, 60])
  #expect(saved.title == reminder.title)
  #expect(try reopened.generation() == 1)
  var other = reminder
  other.id = UUID()
  try reopened.save(other, expectedRevision: nil)
  try reopened.delete(id: reminder.id, expectedRevision: 1)
  #expect(try reopened.list() == [other])
}
