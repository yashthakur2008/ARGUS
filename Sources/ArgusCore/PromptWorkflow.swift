import Foundation

public struct PromptWorkflow: Codable, Equatable, Sendable {
  public let id: String
  public let version: Int64

  public init(id: String, version: Int64) throws {
    guard !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines) else {
      throw PromptError.invalidMetadata
    }
    guard version > 0 else { throw CoreError.invalidRevision }
    self.id = id
    self.version = version
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(String.self, forKey: .id),
      version: values.decode(Int64.self, forKey: .version)
    )
  }
}
