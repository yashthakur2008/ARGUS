import Foundation

/// A delivery intent plus the original reminder occurrences it represents.
/// Several offsets or occurrences may coalesce at the same final fire time.
public struct PlannedNotification: Codable, Equatable, Sendable {
  public let intent: NotificationIntent
  public let occurrenceDates: [Date]

  public init(intent: NotificationIntent, occurrenceDates: [Date]) {
    self.intent = intent
    self.occurrenceDates = Array(Set(occurrenceDates)).sorted()
  }
}
