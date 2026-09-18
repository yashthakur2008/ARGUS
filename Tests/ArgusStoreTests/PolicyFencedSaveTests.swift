import Foundation
import Testing
import ArgusCore
import ArgusStore

struct PolicyFencedSaveTests {
  @Test func matchingPolicyFenceStillEnforcesReminderRevision() throws {
    let (url, item) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try ReminderStore(databaseURL: url)
    try store.save(item, expectedRevision: nil, expectedPolicyRevision: 1)
    var edited = item
    edited.title = "Reviewed edit"
    try store.save(edited, expectedRevision: 1, expectedPolicyRevision: 1)
    let before = try store.list()
    #expect(throws: StoreError.conflict) {
      try store.save(item, expectedRevision: 1, expectedPolicyRevision: 1)
    }
    #expect(try store.list() == before)
    #expect(try store.generation() == 2)
  }

  @Test func stalePolicyCannotInsertButUnfencedSavesRemainCompatible() throws {
    let (url, item) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try ReminderStore(databaseURL: url)
    try store.saveNotificationPolicy(NotificationPolicy(bypassQuietHours: true), expectedRevision: 1)
    #expect(throws: StoreError.conflict) {
      try store.save(item, expectedRevision: nil, expectedPolicyRevision: 1)
    }
    #expect(try store.list().isEmpty)
    #expect(try store.generation() == 1)
    try store.save(item, expectedRevision: nil)
    #expect(try store.list() == [item])
    #expect(try store.generation() == 2)
  }

  @Test func stalePolicySnapshotCannotCommitReminder() throws {
    let (url, item) = try fixture()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let store = try ReminderStore(databaseURL: url)
    try store.save(item, expectedRevision: nil)
    let policy = try store.notificationPolicy()
    let otherConnection = try ReminderStore(databaseURL: url)
    try otherConnection.saveNotificationPolicy(NotificationPolicy(bypassQuietHours: true), expectedRevision: policy.revision)
    let generation = try store.generation()
    var edited = item
    edited.snoozedUntil = item.dueAt.addingTimeInterval(600)
    edited.snoozedOccurrenceAt = item.dueAt
    #expect(throws: StoreError.conflict) {
      try store.save(edited, expectedRevision: 1, expectedPolicyRevision: policy.revision)
    }
    let reopened = try ReminderStore(databaseURL: url)
    #expect(try reopened.reminder(id: item.id) == item)
    #expect(try reopened.generation() == generation)
    #expect(try reopened.notificationPolicy().revision == policy.revision + 1)
  }
}
