import Foundation
import Testing
@testable import ArgusCore

struct CrossZoneScheduleInvariantTests {
  private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

  @Test func exactGapAndFoldAnchors() throws {
    let cases: [(String, Int, Int, Int, Int, String, String)] = [
      ("America/Los_Angeles", 22, 0, 2, 30, "2026-03-08T09:00:00Z", "2026-03-08T10:00:00Z"),
      ("America/Los_Angeles", 0, 0, 1, 30, "2026-11-01T07:30:00Z", "2026-11-01T08:30:00Z"),
      ("America/Los_Angeles", 0, 0, 1, 30, "2026-11-01T09:15:00Z", "2026-11-01T09:30:00Z"),
      // A backward jump before quiet start does not abandon the selected local end.
      ("America/Los_Angeles", 1, 30, 2, 30, "2026-11-01T08:45:00Z", "2026-11-01T10:30:00Z"),
      // A transition exactly at the nominal candidate must still adjust the endpoint.
      ("America/Los_Angeles", 0, 0, 2, 0, "2026-11-01T08:30:00Z", "2026-11-01T10:00:00Z"),
      ("Australia/Lord_Howe", 22, 0, 2, 15, "2026-10-03T14:45:00Z", "2026-10-03T15:30:00Z"),
      ("Australia/Lord_Howe", 0, 0, 1, 45, "2026-04-04T14:15:00Z", "2026-04-04T14:45:00Z"),
      ("Australia/Lord_Howe", 0, 0, 1, 45, "2026-04-04T15:05:00Z", "2026-04-04T15:15:00Z"),
    ]
    for (zone, sh, sm, eh, em, input, expected) in cases {
      let policy = try QuietHours(startHour: sh, startMinute: sm, endHour: eh, endMinute: em, timeZoneID: zone)
      #expect(policy.nextAllowedDate(for: date(input)) == date(expected), "\(zone): \(input)")
    }
  }

  @Test func fractionalInputEndsAtExactBoundaryAndDateLineFallbackStaysCompatible() throws {
    let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    let fractional = date("2026-09-21T23:59:59Z").addingTimeInterval(0.375)
    #expect(quiet.nextAllowedDate(for: fractional) == date("2026-09-22T07:00:00Z"))
    let apia = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "Pacific/Apia")
    #expect(apia.nextAllowedDate(for: date("2011-12-30T09:00:00Z")) == date("2011-12-30T17:00:00Z"))
  }

  @Test func unrepresentableQuietEndStillRejectsPlanning() throws {
    let upper = Date(timeIntervalSince1970: 253_402_300_800)
    let due = upper.addingTimeInterval(-3600)
    let quiet = try QuietHours(startHour: 22, startMinute: 0, endHour: 7, endMinute: 0, timeZoneID: "UTC")
    let item = try Reminder(title: "Upper supported date", dueAt: due, timeZoneID: "UTC",
      createdAt: due.addingTimeInterval(-3600), updatedAt: due.addingTimeInterval(-3600))
    #expect(quiet.nextAllowedDate(for: due) >= upper)
    #expect(throws: CoreError.invalidDate) {
      try ScheduleCalculator.plannedNotifications(for: item, now: due.addingTimeInterval(-3600),
        horizon: upper.addingTimeInterval(-1), quietHours: quiet)
    }
  }

  // Eight fixed windows, two distinct source zones, two weekday rules, four policy modes.
  // Four-day horizons produce far fewer than the 64-delivery production bound.
  private var windows: [(zone: String, start: String)] { [
    ("America/Los_Angeles", "2026-03-06T00:00:00Z"),
    ("America/Los_Angeles", "2026-10-30T00:00:00Z"),
    ("Australia/Lord_Howe", "2026-04-03T00:00:00Z"),
    ("Australia/Lord_Howe", "2026-10-02T00:00:00Z"),
    ("Africa/Cairo", "2026-04-22T00:00:00Z"),
    ("Africa/Cairo", "2026-10-28T00:00:00Z"),
    ("Asia/Kathmandu", "2026-03-06T00:00:00Z"),
    ("Asia/Kathmandu", "2026-10-30T00:00:00Z"),
  ] }

  @Test func restartRestrictionPreservesCompletePlansAcrossZones() throws {
    for window in windows {
      let start = date(window.start)
      let horizon = start.addingTimeInterval(4 * 86400)
      for sourceZone in ["UTC", window.zone == "Africa/Cairo" ? "Asia/Kathmandu" : "Africa/Cairo"] {
        for hour in [0, 23] {
          let item = try Reminder(id: UUID(uuidString: "00000000-0000-0000-0000-000000000017")!,
            title: "Cross-zone invariant", dueAt: start.addingTimeInterval(-7 * 86400),
            timeZoneID: sourceZone, createdAt: start.addingTimeInterval(-8 * 86400),
            updatedAt: start.addingTimeInterval(-8 * 86400), alertOffsets: [0, 3600, 86400],
            recurrence: .weekdays(hour: hour, minute: 30))
          let original = item
          for mode in 0..<4 {
            let quiet = try QuietHours(startHour: mode == 1 ? 0 : 22, startMinute: 0,
              endHour: mode == 2 ? 22 : (mode == 1 ? 2 : 7), endMinute: 0, timeZoneID: window.zone)
            let bypass = mode == 3
            let label = "\(window.zone) \(window.start) source=\(sourceZone) hour=\(hour) mode=\(mode)"
            let baseline = try ScheduleCalculator.plannedNotifications(for: item, now: start,
              horizon: horizon, quietHours: quiet, bypassQuietHours: bypass)
            try check(baseline, item: item, now: start, horizon: horizon, quiet: quiet, bypass: bypass, label: label)
            for seconds in [12 * 3600, 36 * 3600, 60 * 3600, 84 * 3600] {
              let later = start.addingTimeInterval(Double(seconds))
              let restarted = try ScheduleCalculator.plannedNotifications(for: item, now: later,
                horizon: horizon, quietHours: quiet, bypassQuietHours: bypass)
              #expect(restarted == baseline.filter { $0.intent.fireAt > later }, "\(label) restart=\(seconds)")
              try check(restarted, item: item, now: later, horizon: horizon, quiet: quiet, bypass: bypass, label: label)
            }
            #expect(item == original, "\(label) source must not mutate")
          }
        }
      }
    }
  }

  @Test func quietHoursPerInputInvariantsAroundFixedTransitions() throws {
    for window in windows {
      for (sh, eh, em) in [(22, 7, 0), (0, 1, 45), (22, 2, 15), (9, 9, 0)] {
        let policy = try QuietHours(startHour: sh, startMinute: 0, endHour: eh, endMinute: em, timeZoneID: window.zone)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: window.zone)!
        // 15-minute deterministic samples, no random or time-zone database-wide sweep.
        for step in 0...(4 * 24 * 4) {
          let input = date(window.start).addingTimeInterval(Double(step * 900))
          let output = policy.nextAllowedDate(for: input)
          let local = calendar.dateComponents([.hour, .minute], from: input)
          let minute = local.hour! * 60 + local.minute!
          let start = sh * 60, end = eh * 60 + em
          let quiet = start != end && (start < end ? minute >= start && minute < end : minute >= start || minute < end)
          let label = "\(window.zone) \(input) \(sh)-\(eh):\(em)"
          #expect(output >= input, "\(label) never move backwards")
          #expect(policy.nextAllowedDate(for: output) == output, "\(label) idempotent")
          if !quiet { #expect(output == input, "\(label) outside half-open quiet interval") }
        }
      }
    }
  }

  private func check(_ plans: [PlannedNotification], item: Reminder, now: Date, horizon: Date,
    quiet: QuietHours, bypass: Bool, label: String) throws {
    let dates = plans.map(\.intent.fireAt)
    #expect(dates == Set(dates).sorted(), "\(label) sorted unique delivery dates")
    #expect(Set(plans.map(\.intent.id)).count == plans.count, "\(label) unique IDs")
    #expect(plans.count < 64, "\(label) bounded fixture")
    #expect(plans.allSatisfy { $0.intent.fireAt > now && $0.intent.fireAt <= horizon }, "\(label) window")
    #expect(plans.allSatisfy { !$0.occurrenceDates.isEmpty && $0.occurrenceDates == Set($0.occurrenceDates).sorted() }, "\(label) provenance")
    #expect(plans.map(\.intent) == (try ScheduleCalculator.notifications(for: item, now: now,
      horizon: horizon, quietHours: quiet, bypassQuietHours: bypass)), "\(label) projection")
  }
}
