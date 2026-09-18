import Foundation

/// Immutable trusted-memory snapshot. Never encode this directly into plaintext storage.
public struct PromptVersion: Decodable, Equatable, Sendable {
  public let promptID: UUID
  public let number: Int64
  public let savedAt: Date
  public let metadata: PromptMetadata
  public let body: String
  public let schema: [PromptVariable]
  public let context: [PromptContextItem]
  public let workflow: PromptWorkflow?

  /// Reconstruct an immutable record from trusted fields after protected decoding.
  /// This does not authorize a database append or prove the row belongs to an expected identity.
  public init(promptID: UUID, number: Int64, savedAt: Date, metadata: PromptMetadata,
    body: String, schema: [PromptVariable], context: [PromptContextItem], workflow: PromptWorkflow?) throws {
    guard number > 0 else { throw CoreError.invalidRevision }
    try validateDate(savedAt)
    try validatePromptContent(body: body, schema: schema, context: context, workflow: workflow)
    self.promptID = promptID
    self.number = number
    self.savedAt = savedAt
    self.metadata = metadata
    self.body = body
    self.schema = schema
    self.context = context
    self.workflow = workflow
  }

  /// Build the next version without persisting it or requiring runtime variable values.
  /// Template validation and full encoded-input accounting are pending Task 2 integration.
  public static func save(draft: PromptDraft, number: Int64, now: Date) throws -> PromptVersion {
    try draft.validate()
    try validateDate(now)
    guard now >= draft.modifiedAt else { throw CoreError.invalidDate }
    let (next, overflow) = (draft.baseVersion ?? 0).addingReportingOverflow(1)
    guard !overflow, number == next else { throw CoreError.invalidRevision }
    // Task 2 integration pending: validateTemplate and full canonical encoded-input cap.
    return try PromptVersion(promptID: draft.promptID, number: number, savedAt: now,
      metadata: draft.metadata, body: draft.body, schema: draft.schema,
      context: draft.context, workflow: draft.workflow)
  }

  /// A detached editor value. Invalid supplied revision/date is rejected by validate/save.
  public func editDraft(revision: Int64, now: Date) -> PromptDraft {
    PromptDraft(unvalidatedPromptID: promptID, revision: revision, baseVersion: number,
      modifiedAt: now, metadata: metadata, body: body, schema: schema, context: context, workflow: workflow)
  }

  private enum CodingKeys: String, CodingKey {
    case promptID, number, savedAt, metadata, body, schema, context, workflow
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    try self.init(
      promptID: values.decode(UUID.self, forKey: .promptID),
      number: values.decode(Int64.self, forKey: .number),
      savedAt: values.decode(Date.self, forKey: .savedAt),
      metadata: values.decode(PromptMetadata.self, forKey: .metadata),
      body: values.decode(String.self, forKey: .body),
      schema: values.decode([PromptVariable].self, forKey: .schema),
      context: values.decode([PromptContextItem].self, forKey: .context),
      workflow: values.decodeIfPresent(PromptWorkflow.self, forKey: .workflow)
    )
  }
}
