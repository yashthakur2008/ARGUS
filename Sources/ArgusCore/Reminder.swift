import Foundation

public enum CoreError: Error, Equatable, Sendable {
  case invalidTitle
  case invalidTimeZone(String)
  case invalidDate
  case invalidOffsets
  case invalidRecurrence
  case invalidRevision
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
      let candidates = (2...6).compactMap { weekday in
        calendar.nextDate(
          after: date,
          matching: DateComponents(hour: hour, minute: minute, second: 0, weekday: weekday),
          matchingPolicy: .nextTime, repeatedTimePolicy: .first)
      }
      guard let next = candidates.min() else { throw CoreError.invalidDate }
      try validateDate(next)
      return next
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
  public var isCompleted: Bool

  public init(
    id: UUID = UUID(), title: String, dueAt: Date, timeZoneID: String,
    createdAt: Date, updatedAt: Date, revision: Int64 = 1,
    alertOffsets: [TimeInterval] = [0], recurrence: RecurrenceRule? = nil,
    snoozedUntil: Date? = nil, isCompleted: Bool = false
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
    guard revision > 0 else { throw CoreError.invalidRevision }
  }
}

func validatedTitle(_ title: String) throws -> String {
  let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
  guard !trimmed.isEmpty, trimmed.count <= 512 else { throw CoreError.invalidTitle }
  return trimmed
}

func validatedZone(_ identifier: String) throws -> TimeZone {
  guard
    TimeZone.knownTimeZoneIdentifiers.contains(identifier) || identifier == "UTC"
      || identifier == "GMT",
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
