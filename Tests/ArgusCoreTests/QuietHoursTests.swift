import Foundation
import Testing

@testable import ArgusCore

struct QuietHoursTests {
  func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
  @Test func testCrossMidnightAndBoundaries() throws {
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "America/Los_Angeles")
    for text in ["2026-09-21T05:00:00Z", "2026-09-21T06:00:00Z", "2026-09-21T13:59:00Z"] {
      #expect(quiet.nextAllowedDate(for: date(text)) == date("2026-09-21T14:00:00Z"))
    }
    #expect(
      quiet.nextAllowedDate(for: date("2026-09-21T14:00:00Z")) == date("2026-09-21T14:00:00Z"))
  }
  @Test func testSameDayAndDisabled() throws {
    let quiet = try QuietHours(
      startHour: 9, startMinute: 0, endHour: 10, endMinute: 0, timeZoneID: "UTC")
    #expect(
      quiet.nextAllowedDate(for: date("2026-09-21T09:30:00Z")) == date("2026-09-21T10:00:00Z"))
    let disabled = try QuietHours(
      startHour: 9, startMinute: 0, endHour: 9, endMinute: 0, timeZoneID: "UTC")
    #expect(
      disabled.nextAllowedDate(for: date("2026-09-21T09:30:00Z")) == date("2026-09-21T09:30:00Z"))
  }
  @Test func testDSTGapAndFold() throws {
    let gap = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 2, endMinute: 30, timeZoneID: "America/Los_Angeles")
    #expect(gap.nextAllowedDate(for: date("2026-03-08T09:00:00Z")) == date("2026-03-08T10:00:00Z"))
    let fold = try QuietHours(
      startHour: 0, startMinute: 0, endHour: 1, endMinute: 30, timeZoneID: "America/Los_Angeles")
    #expect(fold.nextAllowedDate(for: date("2026-11-01T07:30:00Z")) == date("2026-11-01T08:30:00Z"))
    #expect(fold.nextAllowedDate(for: date("2026-11-01T09:15:00Z")) == date("2026-11-01T09:30:00Z"))
  }
  @Test func testValidationAndCodable() throws {
    #expect(throws: (any Error).self) {
      try QuietHours(startHour: 24, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    }
    #expect(throws: (any Error).self) {
      try QuietHours(startHour: 22, startMinute: -1, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    }
    #expect(throws: (any Error).self) {
      try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 60, timeZoneID: "UTC")
    }
    #expect(throws: (any Error).self) {
      try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "bad")
    }
    let quiet = try QuietHours(
      startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    #expect(try JSONDecoder().decode(QuietHours.self, from: JSONEncoder().encode(quiet)) == quiet)
  }
}

extension QuietHoursTests {
  @Test func testDecodingCannotBypassQuietHoursValidation() {
    let invalid = Data(
      #"{"startHour":25,"startMinute":0,"endHour":7,"endMinute":0,"timeZoneID":"UTC"}"#.utf8)
    #expect(throws: (any Error).self) { try JSONDecoder().decode(QuietHours.self, from: invalid) }
  }
}
