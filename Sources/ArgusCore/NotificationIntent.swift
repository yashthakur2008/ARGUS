import Foundation

/// A data-only plan for the platform adapter, not an instruction to execute.
public struct NotificationIntent: Codable, Equatable, Sendable {
  public static let identifierPrefix = "argus.reminder."
  public let id: String
  public let reminderID: UUID
  public let title: String
  public let fireAt: Date
  public let sourceRevision: Int64

  public init(id: String, reminderID: UUID, title: String, fireAt: Date, sourceRevision: Int64) {
    self.id = id
    self.reminderID = reminderID
    self.title = title
    self.fireAt = fireAt
    self.sourceRevision = sourceRevision
  }
}
