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
    return calendar.nextDate(
      after: date, matching: DateComponents(hour: endHour, minute: endMinute, second: 0),
      matchingPolicy: .nextTime, repeatedTimePolicy: .first) ?? date
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
