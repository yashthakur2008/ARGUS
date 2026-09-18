import Foundation

/// Selected text only. Labels and text belong inside the future protected payload.
public struct PromptContextItem: Decodable, Equatable, Sendable {
  public let id: UUID
  public let label: String
  public let text: String

  public init(id: UUID, label: String, text: String) {
    self.id = id
    self.label = label
    self.text = text
  }
}
