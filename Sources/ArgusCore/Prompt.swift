import Foundation

public enum PromptMembership: String, Codable, Sendable { case inbox, library }

public struct Prompt: Codable, Equatable, Sendable {
  public let id: UUID
  public let createdAt: Date
  public let modifiedAt: Date
  public let revision: Int64
  public let isArchived: Bool
  public let latestVersion: Int64?
  /// The draft belongs to this prompt ID. Its separate revision survives archive/restore.
  public let draftRevision: Int64?

  public init(id: UUID, createdAt: Date, modifiedAt: Date, revision: Int64,
    isArchived: Bool, latestVersion: Int64?, draftRevision: Int64?) throws {
    try validateDate(createdAt)
    try validateDate(modifiedAt)
    guard modifiedAt >= createdAt else { throw CoreError.invalidDate }
    guard revision > 0, latestVersion.map({ $0 > 0 }) ?? true,
      draftRevision.map({ $0 > 0 }) ?? true else { throw CoreError.invalidRevision }
    guard latestVersion != nil || draftRevision != nil else { throw PromptError.invalidMetadata }
    self.id = id
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.revision = revision
    self.isArchived = isArchived
    self.latestVersion = latestVersion
    self.draftRevision = draftRevision
  }

  public var membership: PromptMembership { latestVersion == nil ? .inbox : .library }
  public var visibleMembership: PromptMembership? { isArchived ? nil : membership }

  public func settingArchived(_ archived: Bool, expectedRevision: Int64, now: Date) throws -> Prompt {
    guard expectedRevision == revision else { throw PromptError.conflict }
    try validateDate(now)
    guard now >= modifiedAt else { throw CoreError.invalidDate }
    let (next, overflow) = revision.addingReportingOverflow(1)
    guard !overflow else { throw CoreError.invalidRevision }
    return try Prompt(id: id, createdAt: createdAt, modifiedAt: now, revision: next,
      isArchived: archived, latestVersion: latestVersion, draftRevision: draftRevision)
  }

  public static func capture(id: UUID, metadata: PromptMetadata, body: String,
    schema: [PromptVariable], context: [PromptContextItem], workflow: PromptWorkflow?,
    now: Date) throws -> PromptDraft {
    try PromptDraft(promptID: id, revision: 1, baseVersion: nil, modifiedAt: now,
      metadata: metadata, body: body, schema: schema, context: context, workflow: workflow)
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      id: values.decode(UUID.self, forKey: .id),
      createdAt: values.decode(Date.self, forKey: .createdAt),
      modifiedAt: values.decode(Date.self, forKey: .modifiedAt),
      revision: values.decode(Int64.self, forKey: .revision),
      isArchived: values.decode(Bool.self, forKey: .isArchived),
      latestVersion: values.decodeIfPresent(Int64.self, forKey: .latestVersion),
      draftRevision: values.decodeIfPresent(Int64.self, forKey: .draftRevision)
    )
  }
}
