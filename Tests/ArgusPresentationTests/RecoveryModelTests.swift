import Foundation
import Testing
import ArgusCore
import ArgusStore
import ArgusPlatform
@testable import ArgusPresentation

@MainActor struct RecoveryModelTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func fixture() throws -> (AppModel, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("recovery.sqlite"))
    let now = self.now
    return (AppModel(store: store, client: FakeNotifications(), clock: { now }), dir)
  }
  func source(_ model: AppModel, title: String = "Fixture", offsets: [TimeInterval] = [0]) throws -> Reminder {
    let item = try Reminder(title: title, dueAt: now.addingTimeInterval(-3600), timeZoneID: "UTC", createdAt: now.addingTimeInterval(-7200), updatedAt: now, alertOffsets: offsets)
    try model.store.save(item, expectedRevision: nil)
    return item
  }
  @Test func deniedPermissionCapturesDistinctSummaryAndDismissalSurvivesRestart() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    _ = try source(model, offsets: [0, 300])
    _ = try source(model, title: "Second fixture")
    await model.refresh()
    #expect(model.recovery.activeNotices.count == 3)
    #expect(model.recovery.attentionCount == 2)
    let notice = try #require(model.recovery.activeNotices.first)
    #expect(model.recovery.dismiss(notice, now: now))
    let reopenedStore = try ReminderStore(databaseURL: dir.appendingPathComponent("recovery.sqlite"))
    let now = self.now
    let reopened = AppModel(store: reopenedStore, client: FakeNotifications(), clock: { now })
    await reopened.refresh()
    await reopened.refresh()
    #expect(reopened.recovery.notices.count == 3)
    #expect(reopened.recovery.activeNotices.count == 2)
    #expect(try reopenedStore.list().allSatisfy { !$0.isCompleted })
  }
  @Test func openMissingSourceAndStaleNoticeSnoozeAreExplicit() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    var item = try source(model)
    await model.refresh()
    let notice = try #require(model.recovery.activeNotices.first)
    #expect(model.recovery.open(notice)?.id == item.id)
    item.title = "Changed"
    try model.store.save(item, expectedRevision: 1)
    #expect(!model.recovery.snooze(notice, occurrenceAt: item.dueAt, until: now.addingTimeInterval(600), expectedRevision: 1, now: now))
    #expect(try model.store.notices().count == 1)
    try model.store.delete(id: item.id, expectedRevision: 2)
    #expect(model.recovery.open(notice) == nil)
    #expect(model.recovery.issue?.contains("no longer exists") == true)
  }
  @Test func exactNoticeSnoozeAndRescheduleRetainHistory() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let item = try source(model)
    await model.refresh()
    let notice = try #require(model.recovery.activeNotices.first)
    #expect(model.recovery.snooze(notice, occurrenceAt: notice.occurrenceDates.first, until: now.addingTimeInterval(600), expectedRevision: item.revision, now: now))
    let saved = try #require(try model.store.reminder(id: item.id))
    #expect(saved.dueAt == item.dueAt)
    #expect(saved.snoozedOccurrenceAt == item.dueAt)
    #expect(try model.store.notices(includeDismissed: true).first?.dismissedAt == now)
    var draft = ReminderDraft(original: saved, now: now, timeZone: .current)
    draft.dueAt = now.addingTimeInterval(7200)
    #expect(await model.save(draft))
    #expect(model.recovery.notices.count == 1)
  }
  @Test func policyPersistsAndStaleSaveRequiresReview() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    await model.refresh()
    let original = try #require(model.recovery.policy)
    let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 8, endMinute: 0, timeZoneID: "Asia/Kolkata")
    let policy = try NotificationPolicy(quietHours: quiet, bypassQuietHours: true)
    #expect(model.recovery.savePolicy(policy, expectedRevision: original.revision))
    #expect(!model.recovery.savePolicy(policy, expectedRevision: original.revision))
    #expect(model.recovery.issue?.contains("review") == true)
    let reopened = try ReminderStore(databaseURL: dir.appendingPathComponent("recovery.sqlite"))
    #expect(try reopened.notificationPolicy().quietHours == quiet)
    #expect(try reopened.notificationPolicy().bypassQuietHours == true)
  }
}
extension RecoveryModelTests {
  @Test func coalescedNoticeNeedsExplicitOccurrenceChoice() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let item = try Reminder(title: "Coalesced fixture", dueAt: now.addingTimeInterval(-86400), timeZoneID: "UTC", createdAt: now.addingTimeInterval(-2 * 86400), updatedAt: now, alertOffsets: [0, 86400], recurrence: .weekdays(hour: 8, minute: 0))
    try model.store.save(item, expectedRevision: nil)
    await model.refresh()
    let notice = try #require(model.recovery.notices.first { $0.occurrenceDates.count > 1 })
    #expect(!model.recovery.snooze(notice, occurrenceAt: nil, until: now.addingTimeInterval(600), expectedRevision: 1, now: now))
    #expect(model.recovery.issue?.contains("Choose") == true)
    #expect(try model.store.reminder(id: item.id)?.revision == 1)
    #expect(model.recovery.snooze(notice, occurrenceAt: notice.occurrenceDates[0], until: now.addingTimeInterval(600), expectedRevision: 1, now: now))
    #expect(try model.store.reminder(id: item.id)?.snoozedOccurrenceAt == notice.occurrenceDates[0])
  }
}
