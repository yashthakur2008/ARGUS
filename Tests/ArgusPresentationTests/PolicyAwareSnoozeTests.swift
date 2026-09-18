import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

@MainActor struct PolicyAwareSnoozeTests {
  @Test(arguments: [false, true], [false, true])
  func quietDeferredSnoozeKeepsOriginalOccurrence(command: Bool, legacy: Bool) async throws {
    let (model, item, dir, now) = try fixture(legacy: legacy)
    defer { try? FileManager.default.removeItem(at: dir) }
    let until = date("2026-09-16T08:00:00Z")
    if command {
      model.commandText = "snooze \(item.id) for 90 minutes"
      await model.submit(timeZone: TimeZone(identifier: "UTC")!)
      #expect(model.commandText.isEmpty)
    } else {
      #expect(await model.snooze(item, until: until))
    }
    let reopened = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let saved = try #require(try reopened.reminder(id: item.id))
    #expect(saved.snoozedOccurrenceAt == item.dueAt)
    #expect(saved.snoozedUntil == until)
    #expect(saved.revision == 2)
    let plan = try reopened.desiredSystemNotifications(now: now)
    #expect(plan.contains { $0.fireAt == until })
    #expect(plan.contains { $0.fireAt == date("2026-09-16T10:00:00Z") })
  }

  @Test(arguments: [false, true], [false, true])
  func bypassOrEffectiveDeadlineSelectsCurrentOccurrence(command: Bool, bypass: Bool) async throws {
    let now = date(bypass ? "2026-09-16T06:30:00Z" : "2026-09-16T07:00:00Z")
    let (model, item, dir, _) = try fixture(bypass: bypass, now: now)
    defer { try? FileManager.default.removeItem(at: dir) }
    if command {
      model.commandText = "snooze \(item.id) for 90 minutes"
      await model.submit(timeZone: TimeZone(identifier: "UTC")!)
      #expect(model.commandText.isEmpty)
    } else {
      #expect(await model.snooze(item, for: 5400))
    }
    let saved = try #require(try model.store.reminder(id: item.id))
    #expect(saved.snoozedOccurrenceAt == date("2026-09-16T10:00:00Z"))
    #expect(saved.snoozedUntil == now.addingTimeInterval(5400))
  }

  @Test func unrepresentableEffectiveDeliveryFailsWithoutWriting() async throws {
    let (model, original, dir, now) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    var item = original
    item.snoozedUntil = Date(timeIntervalSince1970: 253_402_300_800.nextDown)
    try model.store.save(item, expectedRevision: 1)
    let saved = try #require(try model.store.reminder(id: item.id))
    let generation = try model.store.generation()
    #expect(!(await model.snooze(saved, until: now.addingTimeInterval(600))))
    #expect(try model.store.reminder(id: item.id) == saved)
    #expect(try model.store.generation() == generation)
  }

  private func fixture(legacy: Bool = false, bypass: Bool = false,
    now: Date? = nil) throws -> (AppModel, Reminder, URL, Date) {
    let now = now ?? date("2026-09-16T06:30:00Z")
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let store = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let due = date("2026-09-14T10:00:00Z")
    let item = try Reminder(title: "Deferred snooze", dueAt: due, timeZoneID: "UTC",
      createdAt: due, updatedAt: due, recurrence: .weekdays(hour: 10, minute: 0),
      snoozedUntil: date("2026-09-15T22:30:00Z"), snoozedOccurrenceAt: legacy ? nil : due)
    try store.save(item, expectedRevision: nil)
    let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    try store.saveNotificationPolicy(NotificationPolicy(quietHours: quiet, bypassQuietHours: bypass), expectedRevision: 1)
    return (AppModel(store: store, client: FakeNotifications(), clock: { now }), item, dir, now)
  }
  private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
}
