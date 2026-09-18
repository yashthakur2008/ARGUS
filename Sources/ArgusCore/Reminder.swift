import Foundation

public enum CoreError: Error, Equatable, Sendable {
  case invalidTitle
  case invalidTimeZone(String)
  case invalidDate
  case invalidOffsets
  case invalidRecurrence
  case invalidRevision
  case invalidSnooze
  case unsupportedCommand
  case invalidDuration
  case invalidQuietHours
  case invalidHorizon
  case notificationLimitExceeded
}

public enum RecurrenceRule: Codable, Equatable, Sendable {
  case weekdays(hour: Int, minute: Int)

  public func validate() throws {
    switch self {
    case let .weekdays(hour, minute):
      guard (0...23).contains(hour), (0...59).contains(minute) else {
        throw CoreError.invalidRecurrence
      }
    }
  }

  /// Strictly after the injected instant, using Gregorian weekdays and the stored zone.
  public func nextOccurrence(after date: Date, timeZone: TimeZone) throws -> Date {
    try validate()
    try validateDate(date)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    switch self {
    case let .weekdays(hour, minute):
      var day = calendar.startOfDay(for: date)
      // Resolve from before each local day, independently of the caller's position in a fold.
      // Foundation's .first alone can return the second instant when searching between them.
      for _ in 0..<8 {
        let weekday = calendar.component(.weekday, from: day)
        if (2...6).contains(weekday),
          let candidate = calendar.nextDate(
            after: day.addingTimeInterval(-1),
            matching: DateComponents(hour: hour, minute: minute, second: 0),
            matchingPolicy: .nextTime, repeatedTimePolicy: .first),
          calendar.isDate(candidate, inSameDayAs: day), candidate > date
        {
          try validateDate(candidate)
          return candidate
        }
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else {
          throw CoreError.invalidDate
        }
        day = nextDay
      }
      throw CoreError.invalidDate
    }
  }
}

public struct Reminder: Codable, Equatable, Sendable {
  public var id: UUID
  public var title: String
  public var dueAt: Date
  public var timeZoneID: String
  public var createdAt: Date
  public var updatedAt: Date
  public var revision: Int64
  public var alertOffsets: [TimeInterval]
  public var recurrence: RecurrenceRule?
  public var snoozedUntil: Date?
  public var snoozedOccurrenceAt: Date?
  public var isCompleted: Bool

  public init(
    id: UUID = UUID(), title: String, dueAt: Date, timeZoneID: String,
    createdAt: Date, updatedAt: Date, revision: Int64 = 1,
    alertOffsets: [TimeInterval] = [0], recurrence: RecurrenceRule? = nil,
    snoozedUntil: Date? = nil, snoozedOccurrenceAt: Date? = nil, isCompleted: Bool = false
  ) throws {
    self.id = id
    self.title = try validatedTitle(title)
    self.dueAt = dueAt
    self.timeZoneID = timeZoneID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.revision = revision
    self.alertOffsets = try normalizedOffsets(alertOffsets)
    self.recurrence = recurrence
    self.snoozedUntil = snoozedUntil
    self.snoozedOccurrenceAt = snoozedOccurrenceAt
    self.isCompleted = isCompleted
    try validate()
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(UUID.self, forKey: .id),
      title: values.decode(String.self, forKey: .title),
      dueAt: values.decode(Date.self, forKey: .dueAt),
      timeZoneID: values.decode(String.self, forKey: .timeZoneID),
      createdAt: values.decode(Date.self, forKey: .createdAt),
      updatedAt: values.decode(Date.self, forKey: .updatedAt),
      revision: values.decode(Int64.self, forKey: .revision),
      alertOffsets: values.decode([TimeInterval].self, forKey: .alertOffsets),
      recurrence: values.decodeIfPresent(RecurrenceRule.self, forKey: .recurrence),
      snoozedUntil: values.decodeIfPresent(Date.self, forKey: .snoozedUntil),
      snoozedOccurrenceAt: values.decodeIfPresent(Date.self, forKey: .snoozedOccurrenceAt),
      isCompleted: values.decode(Bool.self, forKey: .isCompleted)
    )
  }

  /// Call after mutation and before persistence. Noncanonical titles are rejected.
  public func validate() throws {
    guard try validatedTitle(title) == title else { throw CoreError.invalidTitle }
    _ = try validatedZone(timeZoneID)
    for date in [dueAt, createdAt, updatedAt] { try validateDate(date) }
    if let snoozedUntil { try validateDate(snoozedUntil) }
    _ = try normalizedOffsets(alertOffsets)
    try recurrence?.validate()
    if let target = snoozedOccurrenceAt {
      try validateDate(target)
      guard snoozedUntil != nil, target >= dueAt else { throw CoreError.invalidSnooze }
      if target != dueAt {
        guard let recurrence,
          try recurrence.nextOccurrence(
            after: target.addingTimeInterval(-1), timeZone: validatedZone(timeZoneID)) == target
        else { throw CoreError.invalidSnooze }
      }
    }
    guard revision > 0 else { throw CoreError.invalidRevision }
  }

  /// Select once when applying a snooze, then persist the returned occurrence identity.
  /// Uses today's local occurrence (upcoming or overdue), or the next weekday if none today.
  /// An active snooze keeps its explicit target across repeated snoozes and unrelated edits.
  public func occurrenceToSnooze(at now: Date) throws -> Date {
    try validate()
    try validateDate(now)
    if let snoozedUntil, snoozedUntil > now { return snoozedOccurrenceAt ?? dueAt }
    guard let recurrence, dueAt < now else { return dueAt }
    let zone = try validatedZone(timeZoneID)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    return max(
      dueAt,
      try recurrence.nextOccurrence(
        after: calendar.startOfDay(for: now).addingTimeInterval(-1), timeZone: zone))
  }
}

func validatedTitle(_ title: String) throws -> String {
  let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty, trimmed.count <= 512 else { throw CoreError.invalidTitle }
  return trimmed
}

func validatedZone(_ identifier: String) throws -> TimeZone {
  // Foundation supports canonical names and links omitted from its enumerated list
  // (for example Asia/Kolkata and US/Pacific). Require a structured zone name so
  // its permissive abbreviation/fixed-offset parsing cannot accept ambiguous input.
  let isStructuredName =
    identifier.range(
      of: #"\A[A-Za-z0-9_+-]+(?:/[A-Za-z0-9_+-]+)+\z"#, options: .regularExpression) != nil
  guard isStructuredName || identifier == "UTC" || identifier == "GMT",
    let zone = TimeZone(identifier: identifier)
  else { throw CoreError.invalidTimeZone(identifier) }
  return zone
}

func validateDate(_ date: Date) throws {
  // Gregorian years 0001 through 9999. Finite IEEE extremes are unsafe Calendar inputs.
  let seconds = date.timeIntervalSince1970
  guard seconds.isFinite, seconds >= -62_135_596_800, seconds < 253_402_300_800 else {
    throw CoreError.invalidDate
  }
}

func normalizedOffsets(_ offsets: [TimeInterval]) throws -> [TimeInterval] {
  guard offsets.count <= 8, offsets.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
    throw CoreError.invalidOffsets
  }
  return Set(offsets).sorted()
}
