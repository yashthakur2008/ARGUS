import Foundation
import Testing

@testable import ArgusCore

struct CommandParserTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let zone = TimeZone(identifier: "America/Los_Angeles")!
  let id = UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!
  func parse(_ text: String) throws -> ReminderCommand {
    try CommandParser.parse(text, now: now, timeZone: zone)
  }
  @Test func testRelativeReminderUsesInjectedClock() throws {
    #expect(
      try parse("Remind me to leave in 20 minutes")
        == .create(
          title: "leave", dueAt: now.addingTimeInterval(1200), timeZoneID: zone.identifier,
          recurrence: nil))
  }
  @Test func testRelativeUnits() throws {
    for (unit, seconds) in [
      ("minute", 60.0), ("minutes", 60), ("hour", 3600), ("hours", 3600), ("day", 86400),
      ("days", 86400),
    ] {
      #expect(
        try parse("remind me to work in 2 \(unit)")
          == .create(
            title: "work", dueAt: now.addingTimeInterval(seconds * 2), timeZoneID: zone.identifier,
            recurrence: nil))
    }
  }
  @Test func testFiniteGrammarRejectsInvalidInput() {
    for text in [
      "", "   ", "please do something", "remind me to work in 0 minutes",
      "remind me to work in -1 hour", "remind me to work in 999999999999999999999999 days",
      "remind me to work in 1.5 hours", "remind me to  in 2 minutes", "Every month at 8:30, pay",
      "Every weekday at 24:00, work", "Every weekday at 8:60, work", "delete 123", "list now",
      "help me", "alerts \(id) -1h", "snooze \(id) for 0 minutes",
      "edit \(id) due tomorrow",
    ] { #expect(throws: (any Error).self) { try parse(text) } }
  }
  @Test func testExplicitCommands() throws {
    #expect(try parse("list") == .list)
    #expect(try parse("HELP") == .help)
    #expect(try parse("delete \(id)") == .delete(id: id))
    #expect(
      try parse("snooze \(id) for 10 minutes")
        == .snooze(id: id, until: now.addingTimeInterval(600)))
    #expect(try parse("alerts \(id) 1d,1h,1h") == .setAlerts(id: id, offsets: [3600, 86400]))
    #expect(
      try parse("edit \(id) title New title") == .edit(id: id, title: "New title", dueAt: nil))
    #expect(
      try parse("edit \(id) due 2027-01-15T12:00:00Z")
        == .edit(
          id: id, title: nil, dueAt: ISO8601DateFormatter().date(from: "2027-01-15T12:00:00Z")!))
  }
  @Test func testWeekdayBriefingIsOnlyReminder() throws {
    let friday = ISO8601DateFormatter().date(from: "2026-09-18T16:00:00Z")!
    #expect(
      try CommandParser.parse(
        "Every weekday at 8:30, show my morning briefing", now: friday, timeZone: zone)
        == .create(
          title: "show my morning briefing",
          dueAt: ISO8601DateFormatter().date(from: "2026-09-21T15:30:00Z")!,
          timeZoneID: zone.identifier, recurrence: .weekdays(hour: 8, minute: 30)))
  }
}

extension CommandParserTests {
  @Test func testStrictSelectionAndAlertLimits() throws {
    for text in [
      "delete {\(id)}", "delete \(id) trailing", "alerts \(id) 1h,",
      "alerts \(id) 1h,1h,1h,1h,1h,1h,1h,1h,1h", "edit \(id) due 2026-02-30T10:00:00Z",
      "edit \(id) due 2026-09-21T10:00:00", "remind me to work in 18446744073709551615 days",
    ] { #expect(throws: (any Error).self) { try parse(text) } }
    #expect(throws: (any Error).self) {
      try CommandParser.parse("list", now: Date(timeIntervalSince1970: .nan), timeZone: zone)
    }
  }
  @Test func testTitlesRemainLiteralDataAndCommandsRoundTrip() throws {
    let command = try parse("Remind me to $(touch /tmp/not-an-instruction) in 1 minute")
    guard case let .create(title, _, _, _) = command else {
      Issue.record("Expected create")
      return
    }
    #expect(title == "$(touch /tmp/not-an-instruction)")
    #expect(
      try JSONDecoder().decode(ReminderCommand.self, from: JSONEncoder().encode(command)) == command
    )
  }
}

extension CommandParserTests {
  @Test func testISOEditsPreserveExplicitOffsetsAndFractions() throws {
    #expect(
      try parse("edit \(id) due 2027-01-15T12:00:00+05:30")
        == .edit(id: id, title: nil, dueAt: now.addingTimeInterval(-5400)))
    #expect(
      try parse("edit \(id) due 2027-01-15T08:00:00.125Z")
        == .edit(id: id, title: nil, dueAt: now.addingTimeInterval(0.125)))
    for text in ["2026-01-01T24:00:00Z", "2026-01-01T08:00:00+25:00", "2026-01-01T08:00:00+05:99"] {
      #expect(throws: (any Error).self) { try parse("edit \(id) due \(text)") }
    }
  }
}

extension CommandParserTests {
  @Test func testZeroAlertOffsetsDoNotPermitZeroDurations() throws {
    #expect(try parse("alerts \(id) 0m,10m") == .setAlerts(id: id, offsets: [0, 600]))
    #expect(try parse("alerts \(id) 0h") == .setAlerts(id: id, offsets: [0]))
    #expect(throws: CoreError.invalidDuration) { try parse("snooze \(id) for 0 minutes") }
    #expect(throws: CoreError.invalidDuration) { try parse("remind me to work in 0 minutes") }
  }
}
