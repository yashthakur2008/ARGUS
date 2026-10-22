import Foundation
import Testing
@testable import ArgusCore

/// The grammar must accept how people actually type without becoming open-ended.
struct NaturalCommandInputTests {
  private let zone = TimeZone(identifier: "America/Los_Angeles")!
  private var now: Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 8))!
  }

  private func due(_ text: String) throws -> Date {
    guard case let .create(_, dueAt, _, _) = try CommandParser.parse(
      text, now: now, timeZone: zone) else {
      throw CoreError.unsupportedCommand
    }
    return dueAt
  }

  @Test func abbreviatedUnitsMeanTheSameAsTheirFullWords() throws {
    #expect(try due("remind me to x in 20 mins") == (try due("remind me to x in 20 minutes")))
    #expect(try due("remind me to x in 20 min") == (try due("remind me to x in 20 minutes")))
    #expect(try due("remind me to x in 2 hrs") == (try due("remind me to x in 2 hours")))
    #expect(try due("remind me to x in 2 hr") == (try due("remind me to x in 2 hours")))
  }

  @Test func typingNoiseDoesNotChangeTheCommand() throws {
    let canonical = try due("remind me to x in 20 minutes")

    #expect(try due("remind me to x in 20 minutes.") == canonical)
    #expect(try due("remind me to x in 20 minutes!") == canonical)
    #expect(try due("remind  me  to  x  in  20  minutes") == canonical)
    #expect(try due("  remind me to x in 20 minutes  ") == canonical)
  }

  @Test func titlesKeepTheirOwnPunctuationAndSpacing() throws {
    guard case let .create(title, _, _, _) = try CommandParser.parse(
      "remind me to Ask why? in 5 minutes", now: now, timeZone: zone) else {
      Issue.record("Expected a create command"); return
    }
    // Normalization must not edit the user's words, only surrounding noise.
    #expect(title == "Ask why?")
  }

  @Test func clockTimesResolveToTheNextMatchingLocalInstant() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone

    // 09:00 is still ahead of 08:00, so it means today.
    #expect(try due("remind me to x at 09:00")
      == calendar.date(from: DateComponents(year: 2023, month: 11, day: 14, hour: 9)))
    // 07:00 already passed, so the next one is tomorrow rather than the past.
    #expect(try due("remind me to x at 07:00")
      == calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 7)))
    #expect(try due("remind me to x at 07:00") > now)
  }

  @Test func tomorrowSkipsTodayEvenWhenTheTimeHasNotPassed() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone

    #expect(try due("remind me to x tomorrow at 09:00")
      == calendar.date(from: DateComponents(year: 2023, month: 11, day: 15, hour: 9)))
  }

  @Test func springForwardGapResolvesToARealLocalInstant() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let dayBefore = calendar.date(from: DateComponents(year: 2024, month: 3, day: 9, hour: 12))!

    guard case let .create(_, dueAt, _, _) = try CommandParser.parse(
      "remind me to x tomorrow at 02:30", now: dayBefore, timeZone: zone) else {
      Issue.record("Expected a create command"); return
    }

    // 02:30 does not exist on 2024-03-10 in this zone; adding seconds would
    // silently land an hour off instead of on a real wall-clock instant.
    #expect(dueAt == calendar.date(from: DateComponents(year: 2024, month: 3, day: 10, hour: 3)))
    #expect(calendar.component(.hour, from: dueAt) == 3)
  }

  @Test func impossibleClockTimesAreStillRejected() {
    for text in ["remind me to x at 24:00", "remind me to x at 09:60",
      "remind me to x at 99:99"] {
      #expect(throws: (any Error).self) {
        try CommandParser.parse(text, now: now, timeZone: zone)
      }
    }
  }

  @Test func wideningTheGrammarDidNotMakeItOpenEnded() {
    // Titles are data. A looser parser must not start accepting free text or
    // treating a title as another instruction.
    for text in ["remind me to x in twenty minutes", "remind me to x in 20minutes",
      "remind me to x someday", "remind me to x", "do anything",
      "remind me to  in 5 minutes", "remind me to x in 0 minutes"] {
      #expect(throws: (any Error).self) {
        try CommandParser.parse(text, now: now, timeZone: zone)
      }
    }
  }

  @Test func embeddedCommandWordsStayPartOfTheTitle() throws {
    guard case let .create(title, _, _, recurrence) = try CommandParser.parse(
      "remind me to list and delete old files in 5 minutes", now: now, timeZone: zone) else {
      Issue.record("Expected a create command"); return
    }

    #expect(title == "list and delete old files")
    #expect(recurrence == nil)
  }
}
