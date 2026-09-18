import Foundation

public struct PromptMetadata: Codable, Equatable, Sendable {
  public let title: String
  public let tags: [String]
  public let project: String?
  public let isFavorite: Bool

  public init(title: String, tags: [String], project: String?, isFavorite: Bool) throws {
    self.title = try Self.field(title, limit: 512)
    guard tags.count <= 32 else { throw PromptError.invalidMetadata }
    var displayByKey: [String: String] = [:]
    for tag in tags {
      let display = try Self.field(tag, limit: 128)
      let key = PromptSearchNormalization.v1(display)
      if displayByKey[key] == nil { displayByKey[key] = display }
    }
    self.tags = displayByKey.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
      .compactMap { displayByKey[$0] }
    let trimmedProject = project?.trimmingCharacters(in: .whitespacesAndNewlines)
    self.project = try trimmedProject.flatMap { $0.isEmpty ? nil : try Self.field($0, limit: 512) }
    self.isFavorite = isFavorite
  }

  private static func field(_ value: String, limit: Int) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, trimmed.utf8.count <= limit else { throw PromptError.invalidMetadata }
    return trimmed
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      title: values.decode(String.self, forKey: .title),
      tags: values.decode([String].self, forKey: .tags),
      project: values.decodeIfPresent(String.self, forKey: .project),
      isFavorite: values.decode(Bool.self, forKey: .isFavorite)
    )
  }
}
