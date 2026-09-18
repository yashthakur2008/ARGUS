import Foundation

/// Finite grammar. Input and titles are data, never executable instructions.
public enum CommandParser {
  public static func parse(_ text: String, now: Date, timeZone: TimeZone) throws -> ReminderCommand
  {
    try validateDate(now)
    _ = try validatedZone(timeZone.identifier)
    let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
    switch input.lowercased() {
    case "list": return .list
    case "help": return .help
    default: break
    }
    if let parts = captures(#"remind me to (.+) in ([0-9]+) (minutes?|hours?|days?)"#, input) {
      let due = try addingDuration(parts[1], unit: parts[2], to: now)
      return .create(
        title: try validatedTitle(parts[0]), dueAt: due, timeZoneID: timeZone.identifier,
        recurrence: nil)
    }
    if let parts = captures(#"every weekday at ([0-9]{1,2}):([0-9]{2}),\s*(.+)"#, input),
      let hour = Int(parts[0]), let minute = Int(parts[1])
    {
      let rule = RecurrenceRule.weekdays(hour: hour, minute: minute)
      return .create(
        title: try validatedTitle(parts[2]),
        dueAt: try rule.nextOccurrence(after: now, timeZone: timeZone),
        timeZoneID: timeZone.identifier, recurrence: rule)
    }
    let uuid = #"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})"#
    if let parts = captures("delete " + uuid, input), let id = UUID(uuidString: parts[0]) {
      return .delete(id: id)
    }
    if let parts = captures("snooze " + uuid + #" for ([0-9]+) (minutes?|hours?|days?)"#, input),
      let id = UUID(uuidString: parts[0])
    {
      return .snooze(id: id, until: try addingDuration(parts[1], unit: parts[2], to: now))
    }
    if let parts = captures("edit " + uuid + #" (title|due) (.+)"#, input),
      let id = UUID(uuidString: parts[0])
    {
      if parts[1].lowercased() == "title" {
        return .edit(id: id, title: try validatedTitle(parts[2]), dueAt: nil)
      }
      guard
        captures(
          #"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})"#,
          parts[2]) != nil
      else { throw CoreError.unsupportedCommand }
      let formatter = ISO8601DateFormatter()
      if parts[2].contains(".") { formatter.formatOptions.insert(.withFractionalSeconds) }
      if parts[2].uppercased().hasSuffix("Z") {
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
      } else {
        let suffix = String(parts[2].suffix(6))
        let components = suffix.dropFirst().split(separator: ":")
        guard let hours = Int(components[0]), let minutes = Int(components[1]),
          hours <= 23, minutes <= 59
        else { throw CoreError.invalidDate }
        formatter.timeZone = TimeZone(
          secondsFromGMT: (suffix.first == "-" ? -1 : 1) * (hours * 3600 + minutes * 60))
      }
      guard let date = formatter.date(from: parts[2]) else { throw CoreError.invalidDate }
      try validateDate(date)
      // Foundation's parser otherwise silently normalizes February 30 and hour 24.
      guard formatter.string(from: date).prefix(19) == parts[2].uppercased().prefix(19) else {
        throw CoreError.invalidDate
      }
      return .edit(id: id, title: nil, dueAt: date)
    }
    if let parts = captures("alerts " + uuid + #" (.+)"#, input),
      let id = UUID(uuidString: parts[0])
    {
      let tokens = parts[1].split(separator: ",", omittingEmptySubsequences: false)
      guard tokens.count <= 8 else { throw CoreError.invalidOffsets }
      let offsets = try tokens.map { token -> TimeInterval in
        guard
          let value = captures(
            #"([0-9]+)(m|h|d)"#, String(token).trimmingCharacters(in: .whitespaces))
        else { throw CoreError.invalidOffsets }
        return try duration(value[0], unit: value[1], allowZero: true)
      }
      return .setAlerts(id: id, offsets: try normalizedOffsets(offsets))
    }
    throw CoreError.unsupportedCommand
  }

  private static func captures(_ pattern: String, _ text: String) -> [String]? {
    guard
      let regex = try? NSRegularExpression(
        pattern: "\\A(?:" + pattern + ")\\z", options: [.caseInsensitive]),
      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
    else { return nil }
    return (1..<match.numberOfRanges).compactMap {
      Range(match.range(at: $0), in: text).map { String(text[$0]) }
    }
  }

  private static func duration(_ amount: String, unit: String, allowZero: Bool = false) throws
    -> TimeInterval
  {
    guard let integer = UInt64(amount), allowZero || integer > 0 else {
      throw CoreError.invalidDuration
    }
    let multiplier: UInt64
    switch unit.lowercased() {
    case "m", "minute", "minutes": multiplier = 60
    case "h", "hour", "hours": multiplier = 3600
    case "d", "day", "days": multiplier = 86400
    default: throw CoreError.invalidDuration
    }
    let (seconds, overflow) = integer.multipliedReportingOverflow(by: multiplier)
    guard !overflow, seconds <= 9_007_199_254_740_991 else { throw CoreError.invalidDuration }
    return Double(seconds)
  }

  private static func addingDuration(_ amount: String, unit: String, to now: Date) throws -> Date {
    let result = now.addingTimeInterval(try duration(amount, unit: unit))
    try validateDate(result)
    guard result > now else { throw CoreError.invalidDuration }
    return result
  }
}
