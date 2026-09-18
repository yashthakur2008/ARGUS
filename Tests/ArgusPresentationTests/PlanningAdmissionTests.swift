import Foundation
import Testing
import ArgusCore
import ArgusStore
@testable import ArgusPresentation

extension AppModelTests {
  @Test func unplannableDraftCannotPoisonHealthyReminderRecovery() async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let healthy = try admissionFixture()
    try model.store.save(healthy, expectedRevision: nil)
    await model.refresh()
    let generation = try model.store.generation()
    var draft = ReminderDraft(now: now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "Unplannable offset"
    draft.alertMinutes = "1000000000000"
    #expect(!(await model.save(draft)))
    #expect(try model.store.list() == [healthy])
    #expect(try model.store.generation() == generation)
    await model.refresh()
    #expect(model.noticesUnavailableMessage == nil)
    #expect(model.result != nil)
  }

  @Test func unplannableAlertCommandRetainsInputAndStoredRevision() async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let healthy = try admissionFixture()
    try model.store.save(healthy, expectedRevision: nil)
    let input = "alerts \(healthy.id) 1000000000000m"
    model.commandText = input
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    #expect(model.commandText == input)
    #expect(try model.store.list() == [healthy])
    #expect(try model.store.generation() == 1)
    #expect(model.message?.contains("Could not apply command") == true)
  }

  @Test(arguments: [false, true], [false, true])
  func dormantOffsetsRemainEditable(completed: Bool, command: Bool) async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    var item = try admissionFixture(offsets: [60_000_000_000_000])
    item.isCompleted = completed
    if !completed { item.snoozedUntil = now.addingTimeInterval(600); item.snoozedOccurrenceAt = item.dueAt }
    try model.store.save(item, expectedRevision: nil)
    if command {
      model.commandText = "edit \(item.id) title Renamed"
      await model.submit(timeZone: TimeZone(identifier: "UTC")!)
      #expect(model.commandText.isEmpty)
    } else {
      var draft = ReminderDraft(original: item, now: now, timeZone: .current)
      draft.title = "Renamed"
      #expect(await model.save(draft))
    }
    let reopened = try ReminderStore(databaseURL: dir.appendingPathComponent("test.sqlite"))
    let saved = try #require(try reopened.reminder(id: item.id))
    #expect(saved.title == "Renamed")
    #expect(saved.revision == 2)
    #expect(saved.alertOffsets == item.alertOffsets)
    #expect(saved.snoozedUntil == item.snoozedUntil)
    #expect(saved.isCompleted == item.isCompleted)
  }

  @Test(arguments: [false, true])
  func dueEditCannotReactivateUnplannableDormantOffsets(command: Bool) async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    var item = try admissionFixture(offsets: [60_000_000_000_000])
    item.snoozedUntil = now.addingTimeInterval(600)
    item.snoozedOccurrenceAt = item.dueAt
    try model.store.save(item, expectedRevision: nil)
    let changedDue = now.addingTimeInterval(1200)
    if command {
      let input = "edit \(item.id) due \(ISO8601DateFormatter().string(from: changedDue))"
      model.commandText = input
      await model.submit(timeZone: TimeZone(identifier: "UTC")!)
      #expect(model.commandText == input)
    } else {
      var draft = ReminderDraft(original: item, now: now, timeZone: .current)
      draft.dueAt = changedDue
      #expect(!(await model.save(draft)))
    }
    #expect(try model.store.list() == [item])
    #expect(try model.store.generation() == 1)
  }

  @Test func recurringSnoozeCannotHideOtherUnplannableOccurrences() async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    var item = try admissionFixture(offsets: [60_000_000_000_000])
    item.recurrence = .weekdays(hour: 8, minute: 0)
    try model.store.save(item, expectedRevision: nil)
    #expect(!(await model.snooze(item, for: 600)))
    #expect(try model.store.list() == [item])
    #expect(try model.store.generation() == 1)
  }

  @Test func existingUnplannableRecordCanBeRepairedWithoutMigration() async throws {
    let (model, dir) = try fixture()
    defer { try? FileManager.default.removeItem(at: dir) }
    let healthy = try admissionFixture()
    let invalidPlan = try admissionFixture(offsets: [60_000_000_000_000])
    try model.store.save(healthy, expectedRevision: nil)
    try model.store.save(invalidPlan, expectedRevision: nil)
    await model.refresh()
    #expect(model.noticesUnavailableMessage != nil)
    #expect(model.reminders.contains { $0.id == invalidPlan.id })
    model.commandText = "alerts \(invalidPlan.id) 0m"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    let repaired = try #require(try model.store.reminder(id: invalidPlan.id))
    #expect(repaired.alertOffsets == [0])
    #expect(repaired.createdAt == invalidPlan.createdAt)
    #expect(repaired.revision == 2)
    #expect(try model.store.reminder(id: healthy.id) == healthy)
    #expect(try model.store.generation() == 3)
    #expect(model.noticesUnavailableMessage == nil)
    #expect(model.result != nil)
    #expect(model.commandText.isEmpty)
  }

  private func admissionFixture(offsets: [TimeInterval] = [0]) throws -> Reminder {
    try Reminder(title: "Admission fixture", dueAt: now.addingTimeInterval(3600), timeZoneID: "UTC",
      createdAt: now, updatedAt: now, alertOffsets: offsets)
  }
}
