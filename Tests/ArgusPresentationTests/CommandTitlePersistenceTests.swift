import Foundation
import Testing
import ArgusStore
@testable import ArgusPresentation

@MainActor struct CommandTitlePersistenceTests {
  @Test func typedTitlesSurviveCreateEditAndStoreReopen() async throws {
    let (model, directory) = try AppModelTests().fixture()
    defer { try? FileManager.default.removeItem(at: directory) }
    let title = "A  B\tC!"
    model.commandText = "every weekday at 09:00, \(title)"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    #expect(model.commandText.isEmpty)
    let reminder = try #require(model.reminders.first)
    #expect(reminder.title == title)

    let edited = "Keep  this punctuation..."
    model.commandText = "edit \(reminder.id) title \(edited)"
    await model.submit(timeZone: TimeZone(identifier: "UTC")!)
    #expect(model.commandText.isEmpty)
    #expect(model.reminders.first?.title == edited)
    let reopened = try ReminderStore(databaseURL: directory.appendingPathComponent("test.sqlite"))
    let stored = try #require(reopened.list().first)
    #expect(stored.title == edited)
    #expect(stored.recurrence == reminder.recurrence)
    #expect(stored.dueAt == reminder.dueAt)
    #expect(stored.revision == reminder.revision + 1)
  }
}
