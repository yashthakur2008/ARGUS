import Foundation
import Testing
@testable import ArgusCore

struct CommandTitlePreservationTests {
  let now = Date(timeIntervalSince1970: 1_800_000_000)
  let zone = TimeZone(identifier: "UTC")!
  let id = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!

  @Test func titleFinalCommandsKeepPunctuation() throws {
    for title in ["Ship it!", "Read the appendix.", "Really?!", "Wait...", "!"] {
      let recurring = try CommandParser.parse("every weekday at 09:00, \(title)", now: now, timeZone: zone)
      guard case let .create(actual, _, _, rule) = recurring else {
        Issue.record("Expected recurring create"); continue
      }
      #expect(actual == title)
      #expect(rule != nil)
      let edit = try CommandParser.parse("edit \(id) title \(title)", now: now, timeZone: zone)
      #expect(edit == .edit(id: id, title: title, dueAt: nil))
    }
  }

  @Test func commandWhitespaceIsFlexibleWithoutCollapsingTitleWhitespace() throws {
    let title = "A  B\tC\nD"
    for input in [
      "remind  me\tto \(title) in 5 minutes!",
      "remind me to \(title) at 09:00.",
      "remind me to \(title) tomorrow at 09:00!",
      "every\tweekday at 09:00, \(title)",
    ] {
      guard case let .create(actual, _, _, _) = try CommandParser.parse(input, now: now, timeZone: zone) else {
        Issue.record("Expected create"); continue
      }
      #expect(actual == title)
    }
    #expect(try CommandParser.parse("edit  \(id)\ttitle \(title)", now: now, timeZone: zone)
      == .edit(id: id, title: title, dueAt: nil))
  }

  @Test func dueEditStillToleratesSentencePunctuation() throws {
    let plain = try CommandParser.parse("edit \(id) due 2027-01-15T09:00:00Z", now: now, timeZone: zone)
    #expect(try CommandParser.parse("edit\t\(id)  due 2027-01-15T09:00:00Z!", now: now, timeZone: zone) == plain)
  }
  @Test func nonTitleGrammarStillAcceptsWhitespaceAndSentenceNoise() throws {
    #expect(try CommandParser.parse("alerts\t\(id) 5m,\n 0m!", now: now, timeZone: zone)
      == .setAlerts(id: id, offsets: [0, 300]))
    #expect(try CommandParser.parse("delete\n\(id).", now: now, timeZone: zone) == .delete(id: id))
    #expect(try CommandParser.parse("snooze\t\(id) for\n5 mins!", now: now, timeZone: zone)
      == .snooze(id: id, until: now.addingTimeInterval(300)))
  }

}
