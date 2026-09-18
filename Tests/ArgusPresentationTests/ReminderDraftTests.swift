import Foundation
import Testing
import ArgusCore
@testable import ArgusPresentation

struct ReminderDraftTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  @Test func exactZoneRecurrenceAndOffsets() throws {
    var draft = ReminderDraft(now: now, timeZone: TimeZone(identifier: "UTC")!)
    draft.title = "  Weekday fixture  "
    draft.timeZoneID = "America/Los_Angeles"
    draft.dueAt = now
    draft.weekdays = true
    draft.alertMinutes = "0, 10, 30, 10"
    let item = try draft.reminder(now: now)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: draft.timeZoneID)!
    #expect(item.title == "Weekday fixture")
    #expect(item.timeZoneID == draft.timeZoneID)
    #expect(item.dueAt == now)
    #expect(item.recurrence == .weekdays(hour: calendar.component(.hour, from: now), minute: calendar.component(.minute, from: now)))
    #expect(item.alertOffsets == [0, 600, 1800])
  }
  @Test func editPreservesIdentityAndCreation() throws {
    let original = try Reminder(title: "Original", dueAt: now, timeZoneID: "UTC", createdAt: now.addingTimeInterval(-900), updatedAt: now, revision: 4, alertOffsets: [0, 600])
    var draft = ReminderDraft(original: original, now: now, timeZone: .current)
    draft.title = "Edited"
    draft.dueAt = now.addingTimeInterval(3600)
    let edited = try draft.reminder(now: now.addingTimeInterval(60))
    #expect(edited.id == original.id)
    #expect(edited.revision == 4)
    #expect(edited.createdAt == original.createdAt)
    #expect(edited.updatedAt == now.addingTimeInterval(60))
    #expect(edited.alertOffsets == original.alertOffsets)
    #expect(edited.title == "Edited")
  }
  @Test func invalidEditorValuesAreRejected() throws {
    var draft = ReminderDraft(now: now, timeZone: .current)
    draft.title = "Fixture"
    draft.alertMinutes = "0,not-a-number"
    #expect(throws: (any Error).self) { try draft.reminder(now: now) }
    draft.alertMinutes = "-1"
    #expect(throws: (any Error).self) { try draft.reminder(now: now) }
    draft.alertMinutes = "0"
    draft.timeZoneID = "Imaginary/Zone"
    #expect(throws: (any Error).self) { try draft.reminder(now: now) }
  }
}
extension ReminderDraftTests {
  @Test func titleOnlyEditPreservesDSTGapRecurrence() throws {
    let before = ISO8601DateFormatter().date(from: "2026-04-23T20:00:00Z")!
    let zone = TimeZone(identifier: "Africa/Cairo")!
    guard case let .create(title, due, zoneID, recurrence) = try CommandParser.parse("every weekday at 00:30, Original", now: before, timeZone: zone) else { Issue.record("Expected create"); return }
    let original = try Reminder(title: title, dueAt: due, timeZoneID: zoneID, createdAt: before, updatedAt: before, recurrence: recurrence)
    var draft = ReminderDraft(original: original, now: before, timeZone: zone)
    draft.title = "Renamed"
    #expect(try draft.reminder(now: before).recurrence == .weekdays(hour: 0, minute: 30))
  }
}
