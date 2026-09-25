import Foundation

public struct SettingsIssue: Equatable, Sendable, Identifiable {
  public let id: String
  public let title: String
  public let message: String
  public let primaryAction: String

  public init(id: String, title: String, message: String, primaryAction: String) {
    self.id = id
    self.title = title
    self.message = message
    self.primaryAction = primaryAction
  }
}
