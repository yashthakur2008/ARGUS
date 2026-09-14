import Foundation
import Testing
import ArgusCore
import ArgusStore
import ArgusPlatform
@testable import ArgusPresentation

actor FakeNotifications: NotificationClient {
  func authorizationStatus() async -> NotificationAuthorization { .denied }
  func pending() async throws -> [NotificationIntent] { [] }
  func add(_ intent: NotificationIntent) async throws {}
  func remove(ids: [String]) async {}
}
@MainActor struct AppModelTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func fixture() throws -> (AppModel, URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let instant = now
    return (AppModel(store: store, client: FakeNotifications(), clock: { instant }), dir)
  }
  @Test func commandCreatesAndReloads() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    model.commandText = "remind me to Test fixture in 10 minutes"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    #expect(try model.store.list().count == 1)
    #expect(model.reminders.first?.dueAt == now.addingTimeInterval(600))
    #expect(model.commandText.isEmpty)
  }
  @Test func deleteRequiresConfirmationAndRejectDoesNothing() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let item = try Reminder(title: "Fixture", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    model.commandText = "delete \(item.id)"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    #expect(model.pendingDeletion?.id == item.id)
    #expect(try model.store.list().count == 1)
    model.cancelDeletion()
    await model.confirmDeletion()
    #expect(try model.store.list().count == 1)
  }
  @Test func parseErrorPreservesInput() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    model.commandText = "do something imaginary"
    await model.submit(timeZone: .current)
    #expect(model.commandText == "do something imaginary")
    #expect(model.message != nil)
    #expect(try model.store.list().isEmpty)
  }
}
extension AppModelTests {
  @Test func staleDeleteRequiresFreshReview() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    var item = try Reminder(title: "Before", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    model.commandText = "delete \(item.id)"
    await model.submit(timeZone: .current)
    item.title = "Changed elsewhere"
    try model.store.save(item, expectedRevision: 1)
    await model.confirmDeletion()
    #expect(try model.store.list().count == 1)
    #expect(model.pendingDeletion == nil)
    #expect(model.message?.contains("review") == true)
    model.commandText = "delete \(item.id)"
    await model.submit(timeZone: .current)
    await model.confirmDeletion()
    #expect(try model.store.list().isEmpty)
  }
  @Test func editSnoozeAndAlertsPersistWithRevision() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let item = try Reminder(title: "Fixture", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    for text in ["edit \(item.id) title Updated", "snooze \(item.id) for 20 minutes", "alerts \(item.id) 0m,10m"] {
      model.commandText = text
      await model.submit(timeZone: .current)
    }
    let saved = try #require(model.store.list().first)
    #expect(saved.title == "Updated")
    #expect(saved.snoozedUntil == now.addingTimeInterval(1200))
    #expect(saved.alertOffsets == [0, 600])
    #expect(saved.revision == 4)
    #expect(saved.dueAt == item.dueAt)
    #expect(saved.createdAt == now)
    #expect(model.reminders.first == saved)
  }
}

final class FixtureClock: @unchecked Sendable {
  private let lock = NSLock()
  private var value: Date
  init(_ value: Date) { self.value = value }
  func read() -> Date { lock.withLock { value } }
  func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
}

extension AppModelTests {
  @Test func expiredApprovalDoesNotDelete() async throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let clock = FixtureClock(now)
    let model = AppModel(store: store, client: FakeNotifications(), clock: { clock.read() })
    let item = try Reminder(title: "Fixture", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try store.save(item, expectedRevision: nil)
    model.requestDeletion(item)
    clock.advance(301)
    await model.confirmDeletion()
    #expect(try store.list().count == 1)
    #expect(model.pendingDeletion == nil)
    #expect(model.message?.contains("expired") == true)
  }
  @Test func newModelReopensPersistedCommands() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    model.commandText = "remind me to Reopen fixture in 30 minutes"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let now = self.now
    let reopened = AppModel(store: store, client: FakeNotifications(), clock: { now })
    await reopened.refresh()
    #expect(reopened.reminders == model.reminders)
    #expect(reopened.reminders.count == 1)
    #expect(reopened.status.contains("permission denied"))
  }
  @Test func typedRecurringSnoozePersistsCurrentOccurrence() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let item = try Reminder(title: "Recurring fixture", dueAt: now.addingTimeInterval(-7 * 86400), timeZoneID: "UTC", createdAt: now, updatedAt: now, recurrence: .weekdays(hour: 8, minute: 0))
    try model.store.save(item, expectedRevision: nil)
    model.commandText = "snooze \(item.id) for 20 minutes"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    let saved = try #require(model.store.list().first)
    #expect(saved.snoozedOccurrenceAt == now)
    #expect(saved.dueAt == item.dueAt)
  }
}

actor PermissionProbe {
  var count = 0
  func request() { count += 1 }
}
actor SchedulingNotifications: NotificationClient {
  let authorization: NotificationAuthorization
  let fails: Bool
  var intents: [String: NotificationIntent] = [:]
  init(_ authorization: NotificationAuthorization, fails: Bool = false) {
    self.authorization = authorization; self.fails = fails
  }
  func authorizationStatus() async -> NotificationAuthorization { authorization }
  func pending() async throws -> [NotificationIntent] { Array(intents.values) }
  func add(_ intent: NotificationIntent) async throws {
    if fails { throw PresentationError.reminderNotFound }
    intents[intent.id] = intent
  }
  func remove(ids: [String]) async { for id in ids { intents.removeValue(forKey: id) } }
}

extension AppModelTests {
  @Test func permissionOnlyRequestedByExplicitAction() async throws {
    let (fixture, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let probe = PermissionProbe(), now = self.now
    let model = AppModel(store: fixture.store, client: SchedulingNotifications(.notDetermined), clock: { now }, requestPermission: { await probe.request() })
    await model.refresh()
    model.commandText = "remind me to Permission fixture in 10 minutes"
    await model.submit(timeZone: .current)
    #expect(await probe.count == 0)
    #expect(model.status.contains("not enabled"))
    await model.enableNotifications()
    #expect(await probe.count == 1)
  }
  @Test func statusDistinguishesPendingAndScheduledNotDelivered() async throws {
    let (fixture, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let now = self.now
    let scheduled = AppModel(store: fixture.store, client: SchedulingNotifications(.authorized), clock: { now })
    #expect(scheduled.status.contains("not checked"))
    scheduled.commandText = "remind me to Status fixture in 10 minutes"
    await scheduled.submit(timeZone: .current)
    #expect(scheduled.result?.scheduledCount == 1)
    #expect(scheduled.status.contains("1 notifications scheduled"))
    #expect(!scheduled.status.contains("delivered"))
    let pending = AppModel(store: fixture.store, client: SchedulingNotifications(.authorized, fails: true), clock: { now })
    await pending.refresh()
    #expect(pending.status.contains("scheduling pending"))
    #expect(pending.result?.error != nil)
  }
  @Test func editorSaveAndStaleEditUseRealStore() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    var draft = ReminderDraft(now: now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "Editor fixture"; draft.timeZoneID = "Asia/Kolkata"
    draft.weekdays = true; draft.alertMinutes = "0, 15"
    #expect(await model.save(draft))
    let original = try #require(model.reminders.first)
    var edited = ReminderDraft(original: original, now: now, timeZone: .current)
    edited.title = "Updated editor fixture"
    #expect(await model.save(edited))
    #expect(!(await model.save(edited)))
    #expect(try model.store.list().first?.revision == 2)
    #expect(try model.store.list().first?.timeZoneID == "Asia/Kolkata")
    #expect(model.message?.contains("review") == true)
  }
  @Test func uiSnoozePersistsTargetAndApprovalIsOneUse() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let item = try Reminder(title: "UI fixture", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    await model.snooze(item, until: now.addingTimeInterval(600))
    let snoozed = try #require(model.reminders.first)
    #expect(snoozed.snoozedOccurrenceAt == now)
    #expect(snoozed.snoozedUntil == now.addingTimeInterval(600))
    model.requestDeletion(snoozed)
    await model.confirmDeletion()
    try model.store.save(item, expectedRevision: nil)
    await model.confirmDeletion()
    #expect(try model.store.list().count == 1)
  }
}
extension AppModelTests {
  @Test func replacementWithReusedIDCannotConsumeOldApproval() async throws {
    let (model, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let original = try Reminder(title: "Original fixture", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(original, expectedRevision: nil)
    model.requestDeletion(original)
    try model.store.delete(id: original.id, expectedRevision: 1)
    let replacement = try Reminder(id: original.id, title: "Replacement fixture", dueAt: now, timeZoneID: "UTC", createdAt: now.addingTimeInterval(1), updatedAt: now.addingTimeInterval(1))
    try model.store.save(replacement, expectedRevision: nil)
    await model.confirmDeletion()
    #expect(try model.store.list() == [replacement])
    #expect(model.message?.contains("review") == true)
  }
}
extension AppModelTests {
  @Test func relativeSnoozeUsesFreshClockAfterRefresh() async throws {
    let (fixture, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let clock = FixtureClock(now)
    let model = AppModel(store: fixture.store, client: FakeNotifications(), clock: { clock.read() })
    let item = try Reminder(title: "Relative fixture", dueAt: now, timeZoneID: "UTC", createdAt: now, updatedAt: now)
    try model.store.save(item, expectedRevision: nil)
    await model.refresh()
    clock.advance(23)
    await model.snooze(item, for: 600)
    let saved = try #require(model.store.list().first)
    #expect(saved.snoozedUntil?.timeIntervalSince(saved.updatedAt) == 600)
    #expect(saved.updatedAt == now.addingTimeInterval(23))
    #expect(saved.dueAt == item.dueAt)
  }
  @Test func authorizationNoticeDoesNotDuplicateStatus() async throws {
    let (fixture, dir) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
    let now = self.now
    for authorization in [NotificationAuthorization.notDetermined, .denied] {
      let model = AppModel(store: fixture.store, client: SchedulingNotifications(authorization), clock: { now })
      await model.refresh()
      #expect(model.schedulingNotice == nil)
      #expect(model.result?.error != nil)
    }
  }
}
