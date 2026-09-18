import Foundation

public struct QuietHours: Codable, Equatable, Sendable {
  public let startHour: Int
  public let startMinute: Int
  public let endHour: Int
  public let endMinute: Int
  public let timeZoneID: String

  public init(startHour: Int, startMinute: Int, endHour: Int, endMinute: Int, timeZoneID: String)
    throws
  {
    guard (0...23).contains(startHour), (0...23).contains(endHour),
      (0...59).contains(startMinute), (0...59).contains(endMinute)
    else { throw CoreError.invalidQuietHours }
    _ = try validatedZone(timeZoneID)
    self.startHour = startHour
    self.startMinute = startMinute
    self.endHour = endHour
    self.endMinute = endMinute
    self.timeZoneID = timeZoneID
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      startHour: values.decode(Int.self, forKey: .startHour),
      startMinute: values.decode(Int.self, forKey: .startMinute),
      endHour: values.decode(Int.self, forKey: .endHour),
      endMinute: values.decode(Int.self, forKey: .endMinute),
      timeZoneID: values.decode(String.self, forKey: .timeZoneID))
  }

  /// Half-open local interval [start, end). Equal endpoints disable deferral.
  public func nextAllowedDate(for date: Date) -> Date {
    guard (try? validateDate(date)) != nil else { return date }
    let start = startHour * 60 + startMinute
    let end = endHour * 60 + endMinute
    guard start != end else { return date }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneID)!
    let local = calendar.dateComponents([.hour, .minute], from: date)
    let minute = local.hour! * 60 + local.minute!
    let isQuiet =
      start < end ? (minute >= start && minute < end) : (minute >= start || minute < end)
    guard isQuiet else { return date }
    // Foundation nextDate can skip Lord Howe's half-hour gap/second fold until
    // the following day. Preserve the selected next local end through offset changes.
    // This bounded path is not a proof over all historical political transitions:
    // unusual jumps, missing transition information or failed checks use the legacy matcher.
    func legacyEnd() -> Date {
      calendar.nextDate(after: date,
        matching: DateComponents(hour: endHour, minute: endMinute, second: 0),
        matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? date
    }
    let parts = calendar.dateComponents([.second, .nanosecond], from: date)
    var remaining = Double((end - minute + 1440) % 1440) * 60
      - Double(parts.second!) - Double(parts.nanosecond!) / 1_000_000_000
    var cursor = date
    let zone = calendar.timeZone
    for _ in 0..<8 {
      guard remaining.isFinite, remaining > 0 else { return legacyEnd() }
      let candidate = cursor.addingTimeInterval(remaining)
      guard candidate.timeIntervalSinceReferenceDate.isFinite, candidate > cursor else {
        return legacyEnd()
      }
      // Retain the existing out-of-range end so planning rejects it, rather than
      // pretending the still-quiet input is allowed. Do not decompose unsupported dates.
      guard (try? validateDate(candidate)) != nil else { return candidate }
      let offset = zone.secondsFromGMT(for: cursor)
      guard let transition = zone.nextDaylightSavingTimeTransition(after: cursor),
        transition <= candidate else {
        let final = calendar.dateComponents([.hour, .minute, .second], from: candidate)
        guard zone.secondsFromGMT(for: candidate) == offset,
          final.hour == endHour, final.minute == endMinute, final.second == 0
        else { return legacyEnd() }
        return candidate
      }
      guard transition > cursor else { return legacyEnd() }
      let change = zone.secondsFromGMT(for: transition) - offset
      guard abs(change) < 86400 else { return legacyEnd() }
      remaining -= transition.timeIntervalSince(cursor) + Double(change)
      cursor = transition
      if remaining <= 0 {
        let wall = calendar.dateComponents([.hour, .minute], from: transition)
        let value = wall.hour! * 60 + wall.minute!
        let stillQuiet = start < end ? (value >= start && value < end) : (value >= start || value < end)
        return stillQuiet ? legacyEnd() : transition
      }
    }
    return legacyEnd()
  }

  /// A prior local day's alerts can still be pending after a midnight-crossing interval.
  /// Calendar days, rather than 86,400 seconds, preserve this bound across DST changes.
  func candidateSearchStart(for now: Date) -> Date {
    guard startHour != endHour || startMinute != endMinute else { return now }
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: timeZoneID)!
    return calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
  }
}
