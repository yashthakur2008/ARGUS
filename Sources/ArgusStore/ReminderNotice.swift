import Foundation

/// A due scheduled instant, not evidence of an OS delivery.
public struct ReminderNotice: Equatable, Sendable, Identifiable {
  public let id: String
  public let reminderID: UUID
  public let titleSnapshot: String
  public let scheduledAt: Date
  public let sourceRevision: Int64
  public let capturedAt: Date
  public let occurrenceDates: [Date]
  public let dismissedAt: Date?
}

public struct NoticeCaptureResult: Equatable, Sendable {
  public let insertedCount: Int
  public let activeCount: Int
  public let recurringScanStart: Date
}
