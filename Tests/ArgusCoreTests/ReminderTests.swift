import Foundation
import Testing

@testable import ArgusCore

struct ReminderTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  func make(
    title: String = "  Work \n", zone: String = "America/Los_Angeles", offsets: [TimeInterval] = [0]
  ) throws -> Reminder {
    try Reminder(
      title: title, dueAt: now, timeZoneID: zone, createdAt: now, updatedAt: now,
      alertOffsets: offsets)
  }
  @Test func testValidatedDefaultsAndRoundTrip() throws {
    let reminder = try make(offsets: [3600, 0, 3600])
    #expect(reminder.title == "Work")
    #expect(reminder.alertOffsets == [0, 3600])
    #expect(reminder.revision == 1)
    #expect(!(reminder.isCompleted))
    #expect(
      try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(reminder)) == reminder)
  }
  @Test func testInvalidModelInputs() throws {
    for title in [" \n", String(repeating: "x", count: 513)] {
      #expect(throws: (any Error).self) { try make(title: title) }
    }
    #expect(throws: (any Error).self) { try make(zone: "not/a-zone") }
    for offsets in [[-1.0], [.infinity], [.nan], Array(repeating: 0.0, count: 9)] {
      #expect(throws: (any Error).self) { try make(offsets: offsets) }
    }
    var reminder = try make()
    reminder.dueAt = Date(timeIntervalSince1970: .infinity)
    #expect(throws: (any Error).self) { try reminder.validate() }
    reminder = try make()
    reminder.recurrence = .weekdays(hour: 24, minute: 0)
    #expect(throws: (any Error).self) { try reminder.validate() }
    reminder.recurrence = .weekdays(hour: 8, minute: -1)
    #expect(throws: (any Error).self) { try reminder.validate() }
    reminder = try make()
    reminder.snoozedUntil = Date(timeIntervalSince1970: .nan)
    #expect(throws: (any Error).self) { try reminder.validate() }
  }
}

extension ReminderTests {
  @Test func testDecodingRejectsInvalidDataAndNormalizesDuplicates() throws {
    var invalid = try make()
    invalid.title = "  "
    let data = try JSONEncoder().encode(invalid)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(Reminder.self, from: data) }
    var duplicate = try make()
    duplicate.alertOffsets = [3600, 3600, 0]
    let decoded = try JSONDecoder().decode(Reminder.self, from: JSONEncoder().encode(duplicate))
    #expect(decoded.alertOffsets == [0, 3600])
  }
  @Test func testAllTimestampFieldsAndMutationsAreValidated() throws {
    var item = try make()
    item.createdAt = Date(timeIntervalSince1970: .nan)
    #expect(throws: (any Error).self) { try item.validate() }
    item = try make()
    item.updatedAt = Date(timeIntervalSince1970: -.infinity)
    #expect(throws: (any Error).self) { try item.validate() }
    item = try make()
    item.title = " untrimmed "
    #expect(throws: (any Error).self) { try item.validate() }
    item = try make()
    item.revision = 0
    #expect(throws: (any Error).self) { try item.validate() }
    #expect(throws: Never.self) { try make(title: String(repeating: "🙂", count: 512), offsets: []) }
  }
}

extension ReminderTests {
  @Test func testFiniteButUnrepresentableDatesAreRejected() throws {
    for seconds in [
      -Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, -62_135_596_801,
      253_402_300_800,
    ] {
      var item = try make()
      item.dueAt = Date(timeIntervalSince1970: seconds)
      #expect(throws: CoreError.invalidDate) { try item.validate() }
    }
  }
}

extension ReminderTests {
  @Test func testRecurrenceCannotReturnDateOutsideSupportedRange() throws {
    let end = Date(timeIntervalSince1970: 253_402_300_799)
    #expect(throws: CoreError.invalidDate) {
      try RecurrenceRule.weekdays(hour: 8, minute: 30).nextOccurrence(
        after: end, timeZone: TimeZone(identifier: "UTC")!)
    }
  }
}
